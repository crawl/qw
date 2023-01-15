------------------
-- Level map data processing

-- Maximum map width. We use this as a general map radius that's guaranteed to
-- reach the entire map, since qw is never given absolute coordinates by crawl.
GXM = 80

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

function set_waypoint()
    magic(control('w') .. waypoint_parity)
    did_waypoint = true
    return true
end

function record_map_mode_search(key, start_hash, count, end_hash)
    local searches = map_mode_searches[waypoint_parity]
    if not searches[key] then
        searches[key] = {}
    end

    if not searches[key][start_hash] then
        searches[key][start_hash]  = {}
    end

    searches[key][start_hash][count] = end_hash
end

function clear_map_data(num)
    feature_searches[num] = {}
    feature_positions[num] = {}
    item_searches[num] = {}
    distance_maps[num] = {}
    mons_distance_maps[num] = {}

    traversal_maps[num] = {}
    for x = -GXM, GXM do
        traversal_maps[num][x] = {}
    end

    map_mode_searches[num] = {}
end

function add_feature_search(feats)
    local feat_search = feature_searches[waypoint_parity]
    for _, feat in ipairs(feats) do
        if not feat_search[feat] then
            feat_search[feat] = true
        end
    end
end

function find_features(radius)
    if not radius then
        radius = GXM
    end

    local feat_search = feature_searches[waypoint_parity]
    local feat_positions = feature_positions[waypoint_parity]
    local traversal_map = traversal_maps[waypoint_parity]
    local i = 1
    for pos in square_iter(origin, radius, true) do
        if USE_COROUTINE and i % 1000 == 0 then
            coroutine.yield()
        end

        local feat = view.feature_at(pos.x, pos.y)
        local dpos = { x = pos.x + waypoint.x,  y = pos.y + waypoint.y }
        if feat_search[feat] then
            if not feat_positions[feat] then
                feat_positions[feat] = {}
            end
            local hash = hash_position(dpos)
            if not feat_positions[feat][hash] then
                feat_positions[feat][hash] = dpos
            end
        end

        if feat ~= "unseen" and traversal_map[dpos.x][dpos.y] == nil then
            traversal_map[dpos.x][dpos.y] = feature_is_traversable(feat)
        end
        i = i + 1
    end
end

function initialize_distance_map(pos, hash, radius)
    local dist_map = {}
    dist_map.pos = pos
    dist_map.hash = hash
    dist_map.radius = radius
    dist_map.map = {}
    for x = -GXM, GXM do
        dist_map.map[x] = {}
    end

    dist_map.map[pos.x][pos.y] = 0
    return dist_map
end

function handle_feature_searches(pos, dist_queues)
    local feat = view.feature_at(pos.x, pos.y)
    if feature_searches[waypoint_parity][feat] then
        local feat_positions = feature_positions[waypoint_parity]
        if not feat_positions[feat] then
            feat_positions[feat] = {}
        end

        local hash = hash_position(pos)
        if not feat_positions[feat][hash] then
            feat_positions[feat][hash] = pos
        end

        local dist_maps = distance_maps[waypoint_parity]
        if not dist_maps[hash] then
            dist_maps[hash] = initialize_distance_map(pos, hash)
        end

        if not dist_queues[hash] then
            dist_queues[hash] = {}
        end
        table.insert(dist_queues[hash], { x = pos.x, y = pos.y })
    end
end

function update_distance_map_pos(pos, dist_map)
    if not dist_map.radius
            or supdist({ x = dist_map.pos.x - pos.x,
                y = dist_map.pos.y - pos.y }) > dist_map.radius then
        return false
    end

    local oldval = dist_map.map[pos.x][pos.y]
    for dpos in adjacent_iter(pos) do
        local val = dist_map.map[dpos.x][dpos.y]
        if val and (not oldval or oldval > val + 1) then
            oldval = val + 1
        end
    end
    if dist_map.map[pos.x][pos.y] ~= oldval then
        dist_map.map[pos.x][pos.y] = oldval
        return true
    end
end

function handle_traversable_pos(pos, dist_queues)
    for hash, dist_map in pairs(distance_maps[waypoint_parity]) do
        if update_distance_map_pos(pos, dist_map) then
            if not dist_queues[hash] then
                dist_queues[hash] = {}
            end
            table.insert(dist_queues[hash], { x = pos.x, y = pos.y })
        end
    end
end

function update_distance_map(dist_map, queue)
    local traversal_map = traversal_maps[waypoint_parity]
    local first = 1
    local last = #queue
    while first <= last do
        if USE_COROUTINE and first % 300 == 0 then
            coroutine.yield()
        end

        local pos = queue[first]
        local val = dist_map.map[x][y] + 1
        for dpos in adjacent_iter(pos) do
            if (not dist_map.radius
                        or supdist(dpos.x - dist_map.pos.x,
                            dpos.y - dist_map.pos.y) <= dist_map.radius)
                    and traversal_map[dpos.x][dpos.y]
                    and (not dist_map.map[dpos.x][dpos.y]
                        or dist_map.map[dpos.x][dpos.y] > val) then
                dist_map.map[dpos.x][dpos.y] = val
                last = last + 1
                queue[last] = dpos
            end
        end
        first = first + 1
    end
end

function record_map_item(name, pos, dist_queues)
    local item_ps = item_positions[waypoint_parity]
    if not item_ps[name] then
        item_ps[name] = {}
    end

    local pos = { x = waypoint.x + x, y = waypoint.y + y }
    local hash = hash_position(pos)
    local dist_maps = distance_maps[waypoint_parity]
    for ih, _ in pairs(item_ps[name]) do
        if ih ~= hash then
            item_ps[name][ih] = nil
            dist_maps[ih] = nil
        end
    end

    item_ps[name][hash] = pos
    dist_maps[hash] = initialize_distance_map(pos, hash)
    if not dist_queues[hash] then
        dist_queues[hash] = {}
    end
    table.insert(dist_queues[hash], pos)
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

        table.insert(map_queue, { x = pos.x + waypoint.x,
            y = pos.y + waypoint.y })
    end

    local traversal_map = traversal_maps[waypoint_parity]
    local dist_queues = {}
    for i, pos in ipairs(map_queue) do
        if USE_COROUTINE and i % 1000 == 0 then
            coroutine.yield()
        end

        local feat = view.feature_at(pos.x - waypoint.x, pos.y - waypoint.y)
        if feat ~= "unseen" then
            handle_feature_searches(pos, dist_queues)
            handle_item_searches(pos, dist_queues)

            if feature_is_traversable(feat) then
                if not traversal_map[pos.x][pos.y] then
                    handle_traversable(pos, dist_queues)
                end
                traversal_map[pos.x][pos.y] = true
            else
                traversal_map[pos.x][pos.y] = false
            end
        end
    end

    for fh, queue in pairs(dist_queues) do
        update_distance_map(distance_maps[waypoint_parity][fh], queue)
    end
end

function update_map_data()
    if num_required_stairs(where_branch, where_dir, DIR.UP) > 0 then
        for _, feat in ipairs(upstairs_features) do
            feature_searches[waypoint_parity][feat] = true
        end
    end

    local exit = branch_exit(where_branch)
    if feature_is_upstairs(exit) then
        feature_searches[waypoint_parity][exit] = true
    end

    if where_depth >= branch_rune_depth(where_branch)
            and not have_branch_runes(where_branch) then
        local rune = branch_rune(where_branch)
        if type(rune) == "string" then
            if c_persist.seen_items[rune] then
                item_searches[waypoint_parity][rune] = true
            end
        else
            for _, r in ipairs(rune) do
                local rune = rune .. " rune of Zot"
                if c_persist.seen_items[rune] then
                    item_searches[waypoint_parity][rune] = true
                end
                item_searches[waypoint_parity][rune] = true
            end
        end
    end

    if at_branch_end("Zot") and not you.have_orb() then
        item_searches[waypoint_parity]["the orb of Zot"] = true
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
    local dist_maps = distance_maps[waypoint_parity]
    local hash = hash_position(pos)
    if not dist_maps[hash] then
        dist_maps[hash] = initialize_distance_map(pos, hash, radius)
        local queue = { pos }
        update_distance_map(dist_maps[hash], queue)
    end
    return dist_maps[hash]
end

function best_move_towards(positions, radius)
    local dist = 10000
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

    if dist < 10000 then
        return move
    end
end

function best_move_towards_position(pos, radius)
    return best_move_towards({ pos }, radius)
end


function get_feature_positions(feat)
    local positions = {}
    local feat_positions = feature_positions[waypoint_parity]
    for _, feat in ipairs(feats) do
        if feat_positions[feat] then
            for _, pos in pairs(feat_positions[feat]) do
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
    local feat_positions = feature_positions[waypoint_parity]
    local feat = view.feature_at(pos.x, pos.y)
    if not feat_positions[feat] then
        feat_positions[feat] = {}
    end
    local gpos = { x = waypoint.x + pos.x, y = waypoint.y + pos.y }
    local hash = hash_position(gpos)
    if not feat_positions[feat][hash] then
        feat_positions[feat][hash] = gpos
    end
end

function add_ignore_mons(mons)
    local name = enemy:name()
    if not util.contains(ignore_list, name) then
        table.insert(ignore_list, name)
        crawl.setopt("runrest_ignore_monster ^= " .. name .. ":1")
        if DEBUG_MODE then
            dsay("Ignoring " .. name .. ".")
        end
    end
end

function remove_ignore_mons(mons)
    for i, name in ipairs(ignore_list) do
        if enemy:name() == name then
            table.remove(ignore_list, i)
            crawl.setopt("runrest_ignore_monster -= " .. name .. ":1")
            if DEBUG_MODE then
                dsay("Unignoring " .. name .. ".")
            end
            return
        end
    end
end

function clear_ignores()
    local size = #ignore_list
    if size > 0 then
        for i = 1, size do
            local name = table.remove(ignore_list)
            crawl.setopt("runrest_ignore_monster -= " .. name .. ":1")
            dsay("Unignoring " .. name .. ".")
        end
    end
end
