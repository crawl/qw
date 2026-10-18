----------------------
-- Distance map updates to the level map data.

const.move = enum({
    "traversable",
    "safe_terrain",
    "safe",
    "retreat",
    "flee",
    "kiting",
})

-- This must be set up after the relevant functions are defined.
function initialize_move_functions()
    qw.move_functions = {
        [const.move.traversable] = map_is_traversable_at,
        [const.move.safe_terrain] = map_feature_is_safe_at,
        [const.move.safe] = map_is_safe_at,
        [const.move.retreat] = retreat_move_check,
        [const.move.flee] = flee_move_check,
        [const.move.kiting] = kiting_move_check,
    }
end

function distance_map_remove(dist_map)
    assert(qw.distance_maps[dist_map.move_type][dist_map.pos.hash])

    if debug_channel("map") then
        dsayf("Removing %s", distance_map_description(dist_map))
    end

    dist_map.map = nil
    qw.distance_maps[dist_map.move_type][dist_map.pos.hash] = nil
end

function distance_map_initialize(move_type, pos)
    local dist_map = {}
    dist_map.pos = util.copy_table(pos)
    dist_map.move_type = move_type
    dist_map.move_function = qw.move_functions[move_type]
    dist_map.map = {}
    dist_map.propagation_queue = {}
    dist_map.propagation_set = {}
    dist_map.update_turns = qw.turns

    if debug_channel("map") then
        dsayf("Creating %s", distance_map_description(dist_map))
    end

    if dist_map.move_function(pos) then
        dist_map.map[pos.hash] = 0
        table.insert(dist_map.propagation_queue, dist_map.pos)
        dist_map.propagation_set[pos.hash] = #dist_map.propagation_queue
        distance_map_propagate(dist_map)
    end

    if not qw.distance_maps[move_type] then
        qw.distance_maps[move_type] = {}
    end

    assert(not qw.distance_maps[move_type][pos.hash])
    qw.distance_maps[move_type][pos.hash] = dist_map

    return dist_map
end

function expire_distance_maps()
    if not qw.distance_maps then
        return
    end

    -- We only keep maps that were updated the previous turn.
    local removed_maps = {}
    for _, maps in pairs(qw.distance_maps) do
        for _, dist_map in pairs(maps) do
            if dist_map.update_turns < qw.turns - 1 then
                table.insert(removed_maps, dist_map)
            end
        end
    end

    for _, dist_map in ipairs(removed_maps) do
        distance_map_remove(dist_map)
    end
end

function distance_map_propagate_to(dist_map, center, pos)
    if positions_equal(pos, dist_map.pos)
            or not dist_map.move_function(pos) then
        return
    end

    local center_dist = dist_map.map[center.hash]
    if not center_dist then
        return
    end

    local dist = dist_map.map[pos.hash]
    if not dist or dist > center_dist + 1 then
        dist_map.map[pos.hash] = center_dist + 1

        local ind = dist_map.propagation_set[pos.hash]
        -- Only queue this position if it's either not in the queue or has
        -- already been processed.
        if not ind or ind < dist_map.propagation_set[center.hash] then
            table.insert(dist_map.propagation_queue, pos)
            dist_map.propagation_set[pos.hash] = #dist_map.propagation_queue
        end
    end
end

function distance_map_propagate(dist_map)
    if #dist_map.propagation_queue == 0 then
        return
    end

    if debug_channel("map") then
        dsayf("Propagating distance map at %s with %d update positions",
            cell_string_from_map_position(dist_map.pos),
            #dist_map.propagation_queue)
    end

    local ind = 1
    while ind <= #dist_map.propagation_queue do
        local center = dist_map.propagation_queue[ind]
        for pos in adjacent_iter(center) do
            distance_map_propagate_to(dist_map, center, pos)
        end

        if qw.coroutine_throttle and ind % 1000 == 0 then
            if debug_channel("map") then
                dsayf("Propagated block %d with %d positions remaining",
                    ind / 1000, #dist_map.propagation_queue - ind + 1)
            end

            coroutine.yield()
        end

        ind = ind + 1
    end

    dist_map.propagation_queue = {}
    dist_map.propagation_set = {}
end

function distance_map_queue_adjacent_validation(dist_map, pos)
    local cur_ind = dist_map.validation_set[pos.hash]
    for apos in adjacent_iter(pos) do
        if not dist_map.move_function(apos) then
            goto continue
        end

        local ind = dist_map.validation_set[apos.hash]
        -- Only queue this position if it's either not in the queue or its
        -- already been processed.
        if not ind or ind < cur_ind then
            table.insert(dist_map.validation_queue, apos)
            dist_map.validation_set[apos.hash] = #dist_map.validation_queue
        end

        ::continue::
    end
end

function distance_map_adjacent_dist(dist_map, pos)
    local min_dist
    for apos in adjacent_iter(pos) do
        if dist_map.move_function(apos) then
            local dist = dist_map.map[apos.hash]
            if dist and (not min_dist or min_dist > dist) then
                min_dist = dist
            end
        end
    end
    return min_dist
end

-- Check that a position's minimum adjacent distance is consistent with its
-- distance.
function distance_map_validate_dist_at(dist_map, pos)
    if positions_equal(dist_map.pos, pos) then
        return
    end

    local adj_dist = distance_map_adjacent_dist(dist_map, pos)
    if adj_dist and adj_dist == dist_map.map[pos.hash] - 1 then
        return
    end

    dist_map.map[pos.hash] = nil
    distance_map_queue_adjacent_validation(dist_map, pos)

    if not dist_map.update_set[pos.hash] and dist_map.move_function(pos) then
        table.insert(dist_map.update_queue, pos)
        dist_map.update_set[pos.hash] = #dist_map.update_queue
    end
end

function distance_map_validate_at(dist_map, pos)
    if not dist_map.map[pos.hash] then
        return
    end

    if dist_map.move_function(pos) then
        distance_map_validate_dist_at(dist_map, pos)
    else
        dist_map.map[pos.hash] = nil
        distance_map_queue_adjacent_validation(dist_map, pos)
    end
end

function distance_map_update_at(dist_map, pos)
    if not dist_map.move_function(pos) then
        return
    end

    if positions_equal(dist_map.pos, pos) then
        dist_map.map[pos.hash] = 0
        return
    end

    local adj_dist = distance_map_adjacent_dist(dist_map, pos)
    if adj_dist then
        dist_map.map[pos.hash] = adj_dist + 1

        -- Distance has changed, so we'll propagate from this center. We don't
        -- need to check that the position is already in the queue, since this
        -- function can only be run once per position.
        table.insert(dist_map.propagation_queue, pos)
        dist_map.propagation_set[pos.hash] = #dist_map.propagation_queue
    end
end

function distance_map_description(dist_map)
    return enum_string(dist_map.move_type, const.move)
        .. " distance map to "
        .. cell_string_from_map_position(dist_map.pos)
end

-- Update a distance map. This performs any necessary reset, updates
-- positions in the given queue, and then propagates distance changes based
-- on the distance map's propagation queue. This propagation queue will
-- contain the destination position if the distance map has been reset at all
-- and will also contain any positions that saw
function distance_map_update(dist_map)
    if dist_map.update_turns == qw.turns then
        return
    end

    if debug_channel("map") then
        dsayf("Updating %s", distance_map_description(dist_map))
    end

    dist_map.validation_queue = {}
    dist_map.validation_set = {}
    dist_map.update_queue = {}
    dist_map.update_set = {}
    for i, cell in ipairs(qw.map_queue.update_cells) do
        table.insert(dist_map.validation_queue, cell.map_pos)
        dist_map.validation_set[cell.map_pos.hash] = i

        if dist_map.move_function(cell.map_pos) then
            table.insert(dist_map.update_queue, cell.map_pos)
            dist_map.update_set[cell.map_pos.hash] = i
        end
    end

    local cells = dist_map.validation_queue
    local i = 1
    -- This queue may grow as we process it.
    while i <= #cells do
        distance_map_validate_at(dist_map, cells[i])

        if qw.coroutine_throttle and i % 1000 == 0 then
            if debug_channel("map-all") then
                dsayf("Validated block %d with %d positions remaining for %s",
                    i / 1000, #cells - i, distance_map_description(dist_map))
            end

            coroutine.yield()
        end

        i = i + 1
    end

    cells = dist_map.update_queue
    for i, pos in ipairs(cells) do
        distance_map_update_at(dist_map, pos)

        if qw.coroutine_throttle and i % 1000 == 0 then
            if debug_channel("map-all") then
                dsayf("Updated block %d with %d positions remaining for %s",
                    i / 1000, #cells - i, distance_map_description(dist_map))
            end

            coroutine.yield()
        end
    end

    distance_map_propagate(dist_map)
    dist_map.update_turns = qw.turns
end

function get_distance_map(move_type, pos, no_create)
    local maps = qw.distance_maps[move_type]
    local map
    if maps then
        map = maps[pos.hash]
    end

    if not map then
        if no_create then
            return
        end

        return distance_map_initialize(move_type, pos)
    end

    distance_map_update(map)
    return map
end
