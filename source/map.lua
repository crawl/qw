-- Level map navigation

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
    local wx, wy = travel.waypoint_delta(waypoint_parity)
    local i = 1
    for x, y in square_iter(0, 0, radius, true) do
        if USE_COROUTINE and i % 1000 == 0 then
            coroutine.yield()
        end

        local feat = view.feature_at(x, y)
        local dx = x + wx
        local dy = y + wy
        if feat_search[feat] then
            if not feat_positions[feat] then
                feat_positions[feat] = {}
            end
            local hash = hash_coordinates(dx, dy)
            if not feat_positions[feat][hash] then
                feat_positions[feat][hash] = { x = dx, y = dy }
            end
        end

        if feat ~= "unseen" and traversal_map[dx][dy] == nil then
            traversal_map[dx][dy] = feature_is_traversable(feat)
        end
        i = i + 1
    end
end

function initialize_distance_map(pos)
    local dist_maps = distance_maps[waypoint_parity]
    local hash = hash_position(pos)
    dist_maps[hash] = {}
    for x = -GXM, GXM do
        dist_maps[hash][x] = {}
    end
    dist_maps[hash][pos.x][pos.y] = 0
end

function distance_map_features()
    find_features()
    for _, positions in pairs(feature_positions[waypoint_parity]) do
        distance_map_positions(positions)
    end
end

function handle_feature_search(pos, dist_queues)
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
            initialize_distance_map(pos)
        end

        if not dist_queues[hash] then
            dist_queues[hash] = {}
        end
        table.insert(dist_queues[hash], { x = pos.x, y = pos.y })
    end
end

function handle_traversable(pos, dist_queues)
    for fh, dist_map in pairs(distance_maps[waypoint_parity]) do
        local oldval = dist_map[pos.x][pos.y]
        for dx, dy in adjacent_iter(pos.x, pos.y) do
            local val = dist_map[dx][dy]
            if val and (not oldval or oldval > val + 1) then
                oldval = val + 1
            end
        end
        if dist_map[pos.x][pos.y] ~= oldval then
            dist_map[pos.x][pos.y] = oldval
            if not dist_queues[fh] then
                dist_queues[fh] = {}
            end
            table.insert(dist_queues[fh], { x = pos.x, y = pos.y })
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

        local x = queue[first].x
        local y = queue[first].y
        local val = dist_map[x][y] + 1
        for dx, dy in adjacent_iter(x, y) do
            if traversal_map[dx][dy] then
                if not dist_map[dx][dy] or dist_map[dx][dy] > val then
                    dist_map[dx][dy] = val
                    last = last + 1
                    queue[last] = { x = dx, y = dy }
                end
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

    local wx, wy = travel.waypoint_delta(waypoint_parity)
    local pos = { x = wx + x, y = wy + y }
    local hash = hash_position(pos)
    local dist_maps = distance_maps[waypoint_parity]
    for ih, _ in pairs(item_ps[name]) do
        if ih ~= hash then
            item_ps[name][ih] = nil
            dist_maps[ih] = nil
        end
    end

    item_ps[name][hash] = pos
    initialize_distance_map(pos)
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
    local wx, wy = travel.waypoint_delta(waypoint_parity)
    for x, y in square_iter(0, 0, los_radius, true) do
        local feat = view.feature_at(x, y)
        if feat:find("stone_stairs") then
            record_feature_position(x, y)
            record_stairs(where_branch, where_depth, feat, los_state(x, y))
        elseif feat:find("enter_") then
            record_branch(x, y)
        elseif feat:find("altar_") and feat ~= "altar_ecumenical" then
            record_altar(x, y)
        end

        table.insert(map_queue, { x = x + wx, y = y + wy })
    end

    local traversal_map = traversal_maps[waypoint_parity]
    local dist_queues = {}
    for i, pos in ipairs(map_queue) do
        if USE_COROUTINE and i % 1000 == 0 then
            coroutine.yield()
        end

        local feat = view.feature_at(pos.x - wx, pos.y - wy)
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
        local wx, wy = travel.waypoint_delta(waypoint_parity)
        local feat = view.feature_at(0, 0)
        -- We assume we've landed on the next feature in our current "X<key>"
        -- cycle because the feature at our position uses that key.
        if feature_uses_map_key(map_mode_search_key, feat) then
            record_map_mode_search(map_mode_search_key, map_mode_search_hash,
                map_mode_search_count, hash_coordinates(wx, wy))
        end
        map_mode_search_key = nil
        map_mode_search_hash = nil
        map_mode_search_count = nil
    end
end

function get_distance_map(pos)
    local dist_maps = distance_maps[waypoint_parity]
    local hash = hash_position(pos)
    if not dist_maps[hash] then
        initialize_distance_map(pos)
        local queue = { pos }
        update_distance_map(dist_maps[hash], queue)
    end
    return dist_maps[hash]
end

function best_move_towards(positions)
    local wx, wy = travel.waypoint_delta(waypoint_parity)
    local dist = 10000
    local move = {}
    for _, pos in ipairs(positions) do
        local dist_map = get_distance_map(pos)
        for dx, dy in adjacent_iter(wx, wy) do
            if dist_map[dx][dy] and dist_map[dx][dy] < dist then
                move.x = dx - wx
                move.y = dy - wy
                dist = dist_map[dx][dy]
            end
        end
    end

    if dist < 10000 then
        return move
    end
end

function get_feature_positions(feats, radius)
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

function best_move_towards_features(feats, radius)
    local positions = get_feature_positions(feats, radius)
    if #positions == 0 then
        add_feature_search(feats)
        find_features(radius)
        positions = get_feature_positions(feats, radius)
    end

    return best_move_towards(positions)
end

function record_feature_position(x, y)
    local wx, wy = travel.waypoint_delta(waypoint_parity)
    local feat_positions = feature_positions[waypoint_parity]
    local feat = view.feature_at(x, y)
    if not feat_positions[feat] then
        feat_positions[feat] = {}
    end
    local pos = { x = wx + x, y = wy + y }
    local hash = hash_position(pos)
    if not feat_positions[feat][hash] then
        feat_positions[feat][hash] = pos
    end
end
