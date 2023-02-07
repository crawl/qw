------------------
-- Level map data processing

-- Maximum map width. We use this as a general map radius that's guaranteed to
-- reach the entire map, since qw is never given absolute coordinates by crawl.
GXM = 80
GYM = 70

-- A distance greater than any possible map distance between two squares that
-- represents an unreachable target.
INF_DIST = 10000

-- Autoexplore state enum.
AUTOEXP = {
    "NEEDED",
    "PARTIAL",
    "TRANSPORTER",
    "RUNED_DOOR",
    "FULL",
}

function dir_key(dir)
    return dir == DIR.DOWN and ">" or (dir == DIR.UP and "<" or nil)
end

function update_waypoint_data()
    waypoint_parity = 3 - waypoint_parity
    traversal_map = traversal_maps[waypoint_parity]
    exclusion_map = exclusion_maps[waypoint_parity]
    distance_maps = level_distance_maps[waypoint_parity]
    feature_searches = level_feature_searches[waypoint_parity]
    feature_positions = level_feature_positions[waypoint_parity]
    item_searches = level_item_searches[waypoint_parity]
    map_mode_searches = level_map_mode_searches[waypoint_parity]

    local place = in_portal and "Portal" or where
    if not c_persist.waypoints[place] then
        c_persist.waypoints[place] = c_persist.waypoint_count
        c_persist.waypoint_count = c_persist.waypoint_count + 1
        did_waypoint = true
        magic(control('w') .. waypoint_parity)
        coroutine.yield()
    end

    waypoint.x, waypoint.y = travel.waypoint_delta(c_persist.waypoints[place])

end

function record_map_mode_search(key, start_hash, count, end_hash)
    if not map_mode_searches[key] then
        map_mode_searches[key] = {}
    end

    if not map_mode_searches[key][start_hash] then
        map_mode_searches[key][start_hash]  = {}
    end

    map_mode_searches[key][start_hash][count] = end_hash
end

function clear_map_data(num)
    level_feature_searches[num] = {}
    level_feature_positions[num] = {}
    level_item_searches[num] = {}
    level_distance_maps[num] = {}

    traversal_maps[num] = {}
    for x = -GXM, GXM do
        traversal_maps[num][x] = {}
    end

    exclusion_maps[num] = {}
    for x = -GXM, GXM do
        exclusion_maps[num][x] = {}
    end

    map_mode_searches[num] = {}
end

function add_feature_search(feats)
    for _, feat in ipairs(feats) do
        if not feature_search[feat] then
            feature_search[feat] = true
        end
    end
end

function find_features(radius)
    if not radius then
        radius = GXM
    end

    local i = 1
    for pos in square_iter(origin, radius, true) do
        if COROUTINE_THROTTLE and i % 1000 == 0 then
            coroutine.yield()
        end

        local feat = view.feature_at(pos.x, pos.y)
        local dpos = { x = pos.x + waypoint.x,  y = pos.y + waypoint.y }
        if feature_searches[feat] then
            if not feature_positions[feat] then
                feature_positions[feat] = {}
            end
            local hash = hash_position(dpos)
            if not feature_positions[feat][hash] then
                feature_positions[feat][hash] = dpos
            end
        end

        if feat ~= "unseen" then
            if traversal_map[dpos.x][dpos.y] == nil then
                traversal_map[dpos.x][dpos.y] = feature_is_traversable(feat)
            end

            if exclusion_map[dpos.x][dpos.y] == nil then
                exclusion_map[dpos.x][dpos.y] = travel.is_excluded(pos.x, pos.y)
            end
        end
        i = i + 1
    end
end

function distance_map_initialize(pos, hash, radius)
    local dist_map = {}
    dist_map.pos = pos
    dist_map.hash = hash
    dist_map.radius = radius

    dist_map.map = {}
    for x = -GXM, GXM do
        dist_map.map[x] = {}
    end
    dist_map.map[pos.x][pos.y] = 0
    for x = -GXM, GXM do
        dist_map.excluded_map[x] = {}
    end
    dist_map.excluded_map[pos.x][pos.y] = 0

    dist_map.queue = { { x = pos.x, y = pos.y, became_traversable = true } }
    return dist_map
end

function distance_map_initialize_exclusions(dist_map)
    for x = -GXM, GXM do
        dist_map.excluded_map[x] = {}
        for y = -GYM, GYM do
            dist_map.excluded_map[x][y] = dist_map.map[x][y]
        end
    end
end

function handle_feature_searches(pos, dist_queues)
    local feat = view.feature_at(pos.x, pos.y)
    if feature_searches[feat] then
        if not feature_positions[feat] then
            feature_positions[feat] = {}
        end

        local hash = hash_position(pos)
        if not feature_positions[feat][hash] then
            feature_positions[feat][hash] = pos
        end

        if not distance_maps[hash] then
            distance_maps[hash] = distance_map_initialize(pos, hash)
        end
        table.insert(distance_maps[hash]., { x = pos.x, y = pos.y })
    end
end

function distance_map_best_adjacent(pos, dist_map)
    local best_dist = INF_DIST
    local best_exc_dist = INF_DIST
    for apos in adjacent_iter(pos) do
        if traversal_map[apos.x][apos.y] then
            local dist = dist_map.map[apos.x][apos.y]
             if dist and (not best_dist or best_dist > dist) then
                best_dist = dist
            end

            dist = dist_map.excluded_map[apos.x][apos.y]
            if exclusion_map[apos.x][apos.y]
                    and dist
                    and (not best_exc_dist or best_exc_dist > dist) then
                best_exc_dist = dist
            end
        end
    end
    return best_dist, best_exc_dist
end

function distance_map_update_adjacent_pos(center, pos, dist_map)
    if (dist_map.radius
                and supdist(pos.x - dist_map.pos.x,
                        pos.y - dist_map.pos.y) > dist_map.radius)
            or not traversal_map[pos.x][pos.y] then
        return false
    end

    local center_dist = dist_map.map[center.x][center.y]
    local dist = dist_map.map[pos.x][pos.y]
    if center.became_traversable
            and (not dist or dist > center_dist + 1) then
        dist_map.map[pos.x][pos.y] = center_dist + 1

        if exclusion_map[pos.x][pos.y] then
            center_dist = dist_map.excluded_map[center.x][center.y]
            dist = dist_map.excluded_map[pos.x][pos.y]
            if not dist or dist > center_dist + 1 then
                dist_map.excluded_map[pos.x][pos.y] = center_dist + 1
            end
        end

        pos.became_traversable = true
        table.insert(queue, pos)
    elseif center.became_untraversable then
        local best_dist, best_exc_dist = distance_map_best_adjacent(pos,
            dist_map)
        if best_dist and dist < best_dist + 1 then
            dist_map.map[pos.x][pos.y] = best_dist + 1
            pos.became_untraversable = true
            table.insert(queue, pos)
        end

        if exclusion_map[pos.x][pos.y] then
            dist = dist_map.excluded_map[pos.x][pos.y]
            if best_exc_dist and dist < best_exc_dist + 1 then
                dist_map.excluded_map[pos.x][pos.y] = best_exc_dist + 1
                if not pos.became_untraversable then
                    pos.became_untraversable = true
                    table.insert(queue, pos)
                end
            end
        end
    elseif center.became_unexcluded then
    elseif center.became_excluded then
    end
end

function distance_map_queue_update(dist_map)
    local ind = 1
    local count = ind
    while ind <= #dist_map.queue do
        if COROUTINE_THROTTLE and count % 300 == 0 then
            coroutine.yield()
        end

        local pos = dist_map.queue[ind]
        for apos in adjacent_iter(pos) do
            distance_map_update_adjacent_pos(pos, apos, dist_map)
        end
        ind = ind + 1
        count = ind
    end
    dist_map.queue = {}
end

function record_map_item(name, pos, dist_queues)
    if not item_positions[name] then
        item_positions[name] = {}
    end

    local pos = { x = waypoint.x + x, y = waypoint.y + y }
    local pos_hash = hash_position(pos)
    for hash, _ in pairs(item_positions[name]) do
        if hash ~= pos_hash then
            item_positions[name][hash] = nil
            distance_maps[hash] = nil
        end
    end

    item_positions[name][pos_hash] = pos
    distance_maps[pos_hash] = distance_map_initialize(pos, pos_hash)
    table.insert(distance_maps[pos_hash].queue, pos)
end

function handle_item_searches(pos, dist_queues)
    -- Don't do an expensive iteration over all items if we don't have an
    -- active search. TODO: Maybe move the search trigger to the autopickup
    -- function so that this optimization is more accurate. Since that happens
    -- before our turn update and hance might require careful coordination, we
    -- do it this way for now.
    local searches = item_searches[waypoint_parity]
    local have_search = false
    for name, _ in pairs(searches) do
        have_search = true
        break
    end
    if not have_search then
        return
    end

    local floor_items = items.get_items_at(pos.x, pos.y)
    if not floor_items then
        return
    end

    for _, it in ipairs(floor_items) do
        local name = it:name()
        if searches[name] then
            record_map_item(name, pos, dist_queues)
            return
        end
    end
end

function distance_map_update_pos(pos, dist_map)
    if dist_map.radius
            and supdist({ x = dist_map.pos.x - pos.x,
                y = dist_map.pos.y - pos.y }) > dist_map.radius then
        return false
    end

    local traversable = traversal_map[pos.x][pos.y]
    local excluded = not exclusion_map[pos.x][pos.y]
    local dist, excluded_dist
    local update_pos
    -- If we're traversable and don't have a map distance, we just became
    -- traversable, so update the map distance from adjacent squares.
    if traversable and not dist_map.map[pos.x][pos.y] then
        local dist, excluded_dist = distance_map_best_adjacent(pos, dist_map)
        dist_map.map[pos.x][pos.y] = dist + 1
        update_pos = pos
        update_pos.became_traversable = true
    -- If we're not traversable yet have a map distance, we just became
    -- untraversable, so nil both map distances.
    elseif not traversable and dist_map.map[pos.x][pos.y] then
        dist_map.map[pos.x][pos.y] = nil
        dist_map.excluded_map[pos.x][pos.y] = nil
        update_pos = pos
        update_pos.became_untraversable = true
    end

    -- We're excluded yet have an excluded distance, so we just became
    -- excluded. If update_pos isn't set, we
    if excluded and dist_map.excluded_map[pos.x][pos.y] then
        dist_map.excluded_map[pos.x][pos.y] = nil
        if not update_pos then
            update_pos = pos
            update_pos.became_excluded = true
        end
    elseif traversable
            and not excluded
            and not dist_map.excluded_map[pos.x][pos.y] then
        if not excluded_dist then
            excluded_dist = select(2, distance_map_best_adjacent(pos, dist_map))
        dist_map.excluded_map[pos.x][pos.y] = best_dist
    end

    if update_pos then
        table.insert(dist_map.queue, update_pos)
    end
end

function los_map_update()
    local map_queue = {}
    for pos in square_iter(origin, los_radius, true) do
        local feat = view.feature_at(pos.x, pos.y)
        if feat:find("stone_stairs") then
            record_feature_position(pos)
            record_stairs(where_branch, where_depth, feat, los_state(pos))
        elseif feat:find("enter_") then
            record_branch(pos)
        elseif feat:find("altar_") and feat ~= "altar_ecumenical" then
            record_altar(pos)
        end

        traversal_map[pos.x][pos.y] = feature_is_traversable(feat)
        exclusion_map[pos.x][pos.y] = travel.is_excluded(pos.x, pos.y)

        table.insert(map_queue, { x = pos.x + waypoint.x,
            y = pos.y + waypoint.y })
    end

    for i, pos in ipairs(map_queue) do
        if COROUTINE_THROTTLE and i % 1000 == 0 then
            coroutine.yield()
        end

        local feat = view.feature_at(pos.x - waypoint.x, pos.y - waypoint.y)
        if feat ~= "unseen" then
            handle_feature_searches(pos)
            handle_item_searches(pos)

            for _, dist_map in pairs(distance_maps) do
                distance_map_update_pos(pos, dist_map)
            end
        end
    end

    for _, dist_map in pairs(distance_maps) do
        distance_map_queue_update(dist_map)
    end
end

function update_map_data()
    if num_required_stairs(where_branch, where_dir, DIR.UP) > 0 then
        for _, feat in ipairs(upstairs_features) do
            feature_searches[feat] = true
        end
    end

    local exit = branch_exit(where_branch)
    if feature_is_upstairs(exit) then
        feature_searches[exit] = true
    end

    if where_depth >= branch_rune_depth(where_branch)
            and not have_branch_runes(where_branch) then
        local rune = branch_rune(where_branch)
        if type(rune) == "string" then
            if c_persist.seen_items[rune] then
                item_searches[rune] = true
            end
        else
            for _, r in ipairs(rune) do
                local rune = rune .. " rune of Zot"
                if c_persist.seen_items[rune] then
                    item_searches[rune] = true
                end
                item_searches[rune] = true
            end
        end
    end

    if at_branch_end("Zot") and not you.have_orb() then
        item_searches["the orb of Zot"] = true
    end

    los_map_update()

    if map_mode_search_key then
        local feat = view.feature_at(0, 0)
        -- We assume we've landed on the next feature in our current "X<key>"
        -- cycle because the feature at our position uses that key.
        if feature_uses_map_key(map_mode_search_key, feat) then
            record_map_mode_search(map_mode_search_key, map_mode_search_hash,
                map_mode_search_count, hash_position(waypoint))
        end
        map_mode_search_key = nil
        map_mode_search_hash = nil
        map_mode_search_count = nil
    end
end

function get_distance_map(pos, radius)
    local hash = hash_position(pos)
    if not distance_maps[hash] then
        distance_maps[hash] = distance_map_initialize(pos, hash, radius)
        distance_map_queue_update(distance_maps[hash])
    end
    return distance_maps[hash]
end

function best_move_towards(positions, radius)
    local dist = INF_DIST
    local move = {}
    for _, pos in ipairs(positions) do
        local dist_map = get_distance_map(pos, radius)
        for dpos in adjacent_iter(waypoint) do
            if dist_map.map[dpos.x][dpos.y]
                    and dist_map.map[dpos.x][dpos.y] < dist then
                move.x = dpos.x - waypoint.x
                move.y = dpos.y - waypoint.y
                dist = dist_map.map[dpos.x][dpos.y]
            end
        end
    end

    if dist < INF_DIST then
        return move
    end
end

function best_move_towards_position(pos, radius)
    return best_move_towards({ pos }, radius)
end


function get_feature_positions(feat)
    local positions = {}
    for _, feat in ipairs(feats) do
        if feature_positions[feat] then
            for _, pos in pairs(feature_positions[feat]) do
                if not radius or supdist(pos.x, pos.y) <= radius then
                    table.insert(positions, pos)
                end
            end
        end
    end
    return positions
end

function best_move_towards_features(feats)
    local positions = get_feature_positions(feats)
    if #positions == 0 then
        add_feature_search(feats)
        find_features(radius)
        positions = get_feature_positions(feats)
    end

    return best_move_towards(positions)
end

function record_feature_position(pos)
    local feat = view.feature_at(pos.x, pos.y)
    if not feature_positions[feat] then
        feature_positions[feat] = {}
    end
    local gpos = { x = waypoint.x + pos.x, y = waypoint.y + pos.y }
    local hash = hash_position(gpos)
    if not feature_positions[feat][hash] then
        feature_positions[feat][hash] = gpos
    end
end

function handle_exclusions()
    in_exclusion = travel.is_excluded(0, 0)

    if incoming_melee_turn == turn_count - 1 or not hp_is_low(50) then
        return
    end

    for _, enemy in ipairs(enemy_list) do
        if enemy:can_melee_player() or enemy:can_move_to_melee_player() then
            incoming_melee_turn = you.turns()
            return
        end
    end

    for _, enemy in ipairs(enemy_list) do
        travel.set_exclude(enemy.x_pos(), enemy.y_pos())
    end
end
