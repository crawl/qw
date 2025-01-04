----------------------
-- Distance map updates to the level map data.

function distance_map_remove(dist_map)
    if debug_channel("map") then
        dsay("Removing " .. (permanent and "permanent" or "temporary")
            .. " distance map at "
            .. cell_string_from_map_position(dist_map.pos))
    end

    dist_map.map = nil
    dist_map.excluded_map = nil
    distance_maps[dist_map.hash] = nil
end

function distance_map_initialize_maps(dist_map, excluded_only)
    local pos_hash = hash_position(dist_map.pos)
    if not excluded_only then
        dist_map.map = {}
        dist_map.map[pos_hash] = 0
    end

    dist_map.excluded_map = {}
    dist_map.excluded_map[pos_hash] = map_is_unexcluded_at(dist_map.pos) and 0
        or nil
end

function distance_map_initialize(pos, permanent, radius)
    if permanent == nil then
        permanent = false
    end

    if debug_channel("map") then
        dsay("Creating " .. (permanent and "permanent" or "temporary")
            .. " distance map at "
            .. cell_string_from_map_position(pos))
    end

    local dist_map = {}

    dist_map.pos = util.copy_table(pos)
    dist_map.hash = hash_position(pos)
    dist_map.permanent = permanent
    dist_map.radius = radius

    distance_map_initialize_maps(dist_map)
    local dest_pos = new_update_position(pos)
    dist_map.queue = { dest_pos }
    return dist_map
end

function distance_map_adjacent_dist(pos, dist_map, map_select)
    local best_dist, best_excluded_dist
    local main_selected = main_map_selected(map_select)
    local excluded_selected = excluded_map_selected(map_select)
    for pos in adjacent_iter(pos) do
        if map_is_traversable_at(pos) then
            local pos_hash = hash_position(pos)
            local dist
            if main_selected then
                dist = dist_map.map[pos_hash]
                if dist and (not best_dist or best_dist > dist) then
                    best_dist = dist
                end
            end

            if excluded_selected then
                dist = dist_map.excluded_map[pos_hash]
                if map_is_unexcluded_at(pos)
                        and dist
                        and (not best_excluded_dist
                            or best_excluded_dist > dist) then
                    best_excluded_dist = dist
                end
            end
        end
    end
    if main_selected then
        return best_dist, best_excluded_dist
    else
        return best_excluded_dist
    end
end

function distance_map_update_adjacent_pos(pos, center, dist_map)
    if positions_equal(pos, dist_map.pos)
            or (dist_map.radius
                    and position_distance(pos, dist_map.pos) > dist_map.radius)
            -- Untraversable cells don't need distance map updates.
            or not map_is_traversable_at(pos) then
        return
    end

    local update_pos
    local center_dist = dist_map.map[hash_position(center)]
    local pos_hash = hash_position(pos)
    local dist = dist_map.map[pos_hash]
    if not center.excluded_only
            and center_dist
            and (not dist or dist > center_dist + 1) then
        dist_map.map[pos_hash] = center_dist + 1

        update_pos = new_update_position(pos)
    end

    center_dist = dist_map.excluded_map[hash_position(center)]
    dist = dist_map.excluded_map[pos_hash]
    if map_is_unexcluded_at(pos)
            and center_dist
            and (not dist or dist > center_dist + 1) then
        dist_map.excluded_map[pos_hash] = center_dist + 1

        if not update_pos then
            update_pos = new_update_position(pos)
            update_pos.excluded_only = true
        end
    end

    if update_pos then
        table.insert(dist_map.queue, update_pos)
    end
end

function distance_map_propagate(dist_map)
    if #dist_map.queue == 0 then
        return
    end

    if debug_channel("map") then
        dsay("Propagating distance map at "
            .. cell_string_from_map_position(dist_map.pos)
            .. " with " .. #dist_map.queue .. " update positions")
    end

    local ind = 1
    local count = ind
    while ind <= #dist_map.queue do
        if qw.coroutine_throttle and count % 300 == 0 then
            if debug_channel("throttle") then
                dsay("Propagated block " .. count / 300
                    .. " with " .. #dist_map.queue - ind
                    .. " positions remaining")
            end

            coroutine.yield()
        end

        local center = dist_map.queue[ind]
        for pos in adjacent_iter(center) do
            distance_map_update_adjacent_pos(pos, center, dist_map)
        end

        ind = ind + 1
        count = ind
    end

    dist_map.queue = {}
end

function new_update_position(pos)
    return {
        x = pos.x,
        y = pos.y,
        hash = hash_position(pos),
        excluded_only = false,
    }
end

function distance_map_update_position(pos, dist_map, map_select)
    if dist_map.radius
            and position_distance(dist_map.pos, pos) > dist_map.radius then
        return
    end

    local traversable = map_is_traversable_at(pos)
    local dist, excluded_dist, update_pos
    local have_adjacent = false
    local pos_hash = hash_position(pos)
    -- If we're traversable and don't have a map distance, we just became
    -- traversable, so update the map distance from adjacent squares.
    if main_map_selected(map_select)
            and traversable
            and not dist_map.map[pos_hash] then
        dist, excluded_dist = distance_map_adjacent_dist(pos, dist_map,
            map_select)
        have_adjacent = true
        if dist then
            dist_map.map[pos_hash] = dist + 1
            update_pos = new_update_position(pos)
        end
    end

    -- We're traversable and not excluded, yet have no excluded distance.
    if excluded_map_selected(map_select)
            and traversable
            and map_is_unexcluded_at(pos)
            and not dist_map.excluded_map[pos_hash] then
        if not have_adjacent then
            excluded_dist = distance_map_adjacent_dist(pos, dist_map,
                const.map_select.excluded)
        end

        if excluded_dist then
            dist_map.excluded_map[pos_hash] = excluded_dist + 1
            if not update_pos then
                update_pos = new_update_position(pos)
                update_pos.excluded_only = true
            end
        end
    end

    if update_pos then
        table.insert(dist_map.queue, update_pos)
    end
end

function update_distance_maps_at_cells(queue, map_select)
    for i, cell in ipairs(queue) do
        if qw.coroutine_throttle and i % 1000 == 0 then
            if debug_channel("throttle") then
                dsay("Updated distance maps in block " .. i / 1000
                    .. " with " .. #queue - i .. " cells remaining")
            end

            coroutine.yield()
        end

        for _, dist_map in pairs(distance_maps) do
            distance_map_update_position(cell.pos, dist_map, map_select)
        end
    end
end

function update_distance_maps(queue, reset)
    local removed_maps = {}
    for _, dist_map in pairs(distance_maps) do
        if not map_is_traversable_at(dist_map.pos) then
            table.insert(removed_maps, dist_map)
        end
    end
    for _, dist_map in ipairs(removed_maps) do
        distance_map_remove(dist_map)
    end

    local excluded_only = reset == const.map_select.excluded
    if reset > const.map_select.none then
        if debug_channel("map") then
            dsay("Resetting "
                .. (excluded_only and "excluded map" or "both maps")
                .. " for all distance maps")
        end

        for hash, dist_map in pairs(distance_maps) do
            distance_map_initialize_maps(dist_map, excluded_only)
            local pos = new_update_position(dist_map.pos)
            pos.excluded_only = excluded_only
            dist_map.queue = { pos }
        end
    end

    if reset < const.map_select.both then
        update_distance_maps_at_cells(queue,
            reset == const.map_select.none and const.map_select.both
                or const.map_select.main)
    end

    for _, dist_map in pairs(distance_maps) do
        distance_map_propagate(dist_map)
    end
end

function get_distance_map(pos, permanent, radius)
    local hash = hash_position(pos)
    if not distance_maps[hash] then
        distance_maps[hash] = distance_map_initialize(pos, permanent, radius)
        distance_map_propagate(distance_maps[hash])
    end
    return distance_maps[hash]
end

function map_is_reachable_at(pos, ignore_exclusions)
    local dist_map = get_distance_map(qw.reachable_position)
    local map = ignore_exclusions and dist_map.map or dist_map.excluded_map
    return map[hash_position(pos)]
end

--[[
Check any feature types flagged in check_reachable_features during the map
update. These have been seen but not are not currently reachable LOS-wise, so
check whether our reachable position distance map indicates they are in fact
reachable, and if so, update their los state.
]]--
function update_reachable_features()
    local check_feats = {}
    for feat, _ in pairs(check_reachable_features) do
        table.insert(check_feats, feat)
    end
    if #check_feats == 0 then
        return
    end

    local positions, feats = get_feature_map_positions(check_feats)
    if #positions == 0 then
        return
    end

    for i, pos in ipairs(positions) do
        if map_is_reachable_at(pos, true) then
            update_feature(where_branch, where_depth, feats[i],
                hash_position(pos), { feat = const.explore.reachable })
        end
    end

    check_reachable_features = {}
end

function update_reachable_position()
    for _, dist_map in pairs(distance_maps) do
        if dist_map.excluded_map[hash_position(qw.map_pos)] then
            qw.reachable_position = dist_map.pos
            return
        end
    end

    qw.reachable_position = qw.map_pos
end
