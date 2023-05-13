------------------
-- Level map data processing

-- Maximum map width. We use this as a general map radius that's guaranteed to
-- reach the entire map, since qw is never given absolute coordinates by crawl.
GXM = 80
GYM = 70

MAX_TEMP_DISTANCE_MAPS = 6

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

function update_waypoint()
    local place = where
    if in_portal() then
        place = "Portal"
    end

    local new_waypoint = false
    local waypoint_num = c_persist.waypoints[place]
    if not waypoint_num then
        waypoint_num = c_persist.waypoint_count
        c_persist.waypoints[place] = waypoint_num
        c_persist.waypoint_count = waypoint_num + 1
        travel.set_waypoint(waypoint_num, 0, 0)
        new_waypoint = true
    end

    global_pos.x, global_pos.y = travel.waypoint_delta(waypoint_num)

    -- The waypoint can become invalid due to entering a new Portal, a new Pan
    -- level, or due to an Abyss shift, etc.
    if not global_pos.x then
        travel.set_waypoint(waypoint_num, 0, 0)
        global_pos.x, global_pos.y = travel.waypoint_delta(waypoint_num)
        new_waypoint = true
    end

    return new_waypoint
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

function clear_map_cache(parity, full_clear)
    if debug_channel("map") then
        dsay((full_clear and "Full clearing" or "Clearing")
            .. " map cache for slot " .. tostring(parity))
    end

    if full_clear then
        map_mode_searches_cache[parity] = {}
    end

    feature_map_positions_cache[parity] = {}
    item_map_positions_cache[parity] = {}
    distance_maps_cache[parity] = {}

    traversal_maps_cache[parity] = {}
    for x = -GXM, GXM do
        traversal_maps_cache[parity][x] = {}
    end

    exclusion_maps_cache[parity] = {}
    for x = -GXM, GXM do
        exclusion_maps_cache[parity][x] = {}
    end
end

function find_features(feats, radius)
    if not radius then
        radius = GXM
    end

    local searches = {}
    for _, feat in ipairs(feats) do
        searches[feat] = true
    end

    local positions = {}
    local found_feats = {}
    local i = 1
    for pos in square_iter(origin, radius, true) do
        if COROUTINE_THROTTLE and i % 1000 == 0 then
            if debug_channel("update") then
                dsay("Searched features in block " .. tostring(i / 1000)
                    .. " of map positions")
            end
            coroutine.yield()
        end

        local feat = view.feature_at(pos.x, pos.y)
        if searches[feat] then
            if not feature_map_positions[feat] then
                feature_map_positions[feat] = {}
            end

            local gpos = position_sum(global_pos, pos)
            local hash = hash_position(gpos)
            if not feature_map_positions[feat][hash] then
                feature_map_positions[feat][hash] = gpos
            end
            table.insert(positions, gpos)
            table.insert(found_feats, feat)
        end

        i = i + 1
    end

    return positions, found_feats
end

function find_items(item_names, radius)
    if not radius then
        radius = GXM
    end

    local searches = {}
    for _, name in ipairs(item_names) do
        searches[name] = true
    end

    local positions = {}
    local found_items = {}
    local i = 1
    for pos in square_iter(origin, radius, true) do
        if COROUTINE_THROTTLE and i % 1000 == 0 then
            if debug_channel("update") then
                dsay("Searched items in block " .. tostring(i / 1000)
                    .. " of map positions")
            end
            coroutine.yield()
        end

        local floor_items = items.get_items_at(pos.x, pos.y)
        if floor_items then
            for _, it in ipairs(floor_items) do
                local name = it:name()
                if searches[name] then
                    local map_pos = position_sum(global_pos, pos)
                    item_map_positions[name] = map_pos
                    table.insert(positions, map_pos)
                    table.insert(found_items, name)

                    searches[name] = nil
                    if table_is_empty(searches) then
                        return positions, found_items
                    end
                end
            end
        end

        i = i + 1
    end

    return positions, found_items
end

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

    dist_map.map = {}
    for x = -GXM, GXM do
        dist_map.map[x] = {}
    end
    dist_map.map[pos.x][pos.y] = 0

    dist_map.excluded_map = {}
    for x = -GXM, GXM do
        dist_map.excluded_map[x] = {}
    end
    dist_map.excluded_map[pos.x][pos.y] = 0

    local dest_pos = new_update_position(pos)
    dest_pos.propagate_traversable = true
    dest_pos.propagate_unexcluded = true
    dist_map.queue = { dest_pos }
    dist_map.queue_next = { dest_pos.hash }
    return dist_map
end

function is_traversable_at(pos)
    local gpos = position_sum(global_pos, pos)
    return traversal_map[gpos.x][gpos.y]
end

function map_is_traversable_at(pos)
    return traversal_map[pos.x][pos.y]
end

function map_is_unseen_at(pos)
    return traversal_map[pos.x][pos.y] == nil
end

function distance_map_adjacent_dist(pos, dist_map)
    local best_dist, best_excluded_dist
    for pos in adjacent_iter(pos) do
        if map_is_traversable_at(pos) then
            local dist = dist_map.map[pos.x][pos.y]
            if dist and (not best_dist or best_dist > dist) then
                best_dist = dist
            end

            dist = dist_map.excluded_map[pos.x][pos.y]
            if map_is_unexcluded_at(pos)
                    and dist
                    and (not best_excluded_dist
                        or best_excluded_dist > dist) then
                best_excluded_dist = dist
            end
        end
    end
    return best_dist, best_excluded_dist
end

function distance_map_update_adjacent_pos(pos, center, dist_map)
    if dist_map.queue_next[pos.hash]
            or positions_equal(pos, dist_map.pos)
            or (dist_map.radius
                and supdist(position_difference(pos, dist_map.pos))
                    > dist_map.radius)
            -- Untraversable cells don't need distance map updates.
            or not map_is_traversable_at(pos) then
        return
    end

    local unexcluded = map_is_unexcluded_at(pos)
    local adjacent_dist, adjacent_excluded_dist, update_pos
    local have_adjacent_excluded = false
    if center.propagate_traversable then
        local center_dist = dist_map.map[center.x][center.y]
        local dist = dist_map.map[pos.x][pos.y]
        if center_dist and (not dist or dist > center_dist + 1) then
            dist_map.map[pos.x][pos.y] = center_dist + 1

            update_pos = new_update_position(pos)
            update_pos.propagate_traversable = true
        end

        center_dist = dist_map.excluded_map[center.x][center.y]
        dist = dist_map.excluded_map[pos.x][pos.y]
        if unexcluded
                and not center.proagate_unexcluded
                and not center.proagate_excluded
                and center_dist
                and (not dist or dist > center_dist + 1) then
            dist_map.excluded_map[pos.x][pos.y] = center_dist + 1

            if not update_pos then
                update_pos = new_update_position(pos)
            end
            update_pos.propagate_traversable = true
        end
    elseif center.propagate_untraversable then
        adjacent_dist, adjacent_excluded_dist = distance_map_adjacent_dist(pos,
            dist_map)
        have_adjacent_excluded = true
        local dist = dist_map.map[pos.x][pos.y]
        local target_dist = adjacent_dist and adjacent_dist + 1 or nil
        if dist ~= target_dist then
            -- If we have a non-nil distance that disagrees with our target
            -- distance, we always set our distance to nil. This way we first
            -- propagate nil to all cells that have an invalid non-nil distance
            -- and update them to to correct non-nil value through later
            -- propagation after all the nils have propagated. Otherwise
            -- invalid distances can increase and propagate indefinitely
            -- between a set of adjacent cells when those cells become
            -- disconnected from the rest of the map due to the traversability
            -- change.
            if dist then
                dist_map.map[pos.x][pos.y] = nil
            else
                dist_map.map[pos.x][pos.y] = target_dist
            end

            update_pos = new_update_position(pos)
            update_pos.propagate_untraversable = true
        end

        target_dist = adjacent_excluded_dist and adjacent_excluded_dist + 1
            or nil
        local excluded_dist = dist_map.excluded_map[pos.x][pos.y]
        if unexcluded
                -- The original cell becoming unexcluded yet also untraversable
                -- means no change to propagate to the excluded map.
                and not center.propagate_unexcluded
                -- If we're also propagating becoming excluded, we'll handle
                -- the update below. This way we don't propagate traversability
                -- further if there was no change to the unexcluded map.
                and not center.propagate_excluded
                and excluded_dist ~= target_dist then
            if excluded_dist then
                dist_map.excluded_map[pos.x][pos.y] = nil
            else
                dist_map.excluded_map[pos.x][pos.y] = target_dist
            end

            if not update_pos then
                update_pos = new_update_position(pos)
            end
            update_pos.propagate_untraversable = true
        end

        if update_pos and debug_channel("update-all") then
            dsay("Propagating untraversability for distance map at "
                .. pos_string(position_difference(dist_map.pos, global_pos))
                .. " via center "
                .. pos_string(position_difference(center, global_pos))
                .. " to position "
                .. pos_string(position_difference(pos, global_pos))
                .. " with original distances "
                .. tostring(dist) .. "/" .. tostring(excluded_dist)
                .. " and adjacent distances "
                .. tostring(adjacent_dist) .. "/"
                .. tostring(adjacent_excluded_dist)
                .. " and new distances "
                .. tostring(dist_map.map[pos.x][pos.y])
                .. "/" .. tostring(dist_map.excluded_map[pos.x][pos.y]))
        end
    end

    -- No change to propagate to the excluded map if the original cell became
    -- unexcluded yet also untraversable, since the original cell's excluded
    -- map had a nil distance and still has a nil distance.
    if not center.propagate_untraversable
            and center.propagate_unexcluded
            and unexcluded then
        local center_dist = dist_map.excluded_map[center.x][center.y]
        local dist = dist_map.excluded_map[pos.x][pos.y]
        if center_dist and (not dist or dist > center_dist + 1) then
            dist_map.excluded_map[pos.x][pos.y] = center_dist + 1

            if not update_pos then
                update_pos = new_update_position(pos)
            end
            update_pos.propagate_unexcluded = true
        end
    -- No change to propagate to the excluded map if the original cell became
    -- excluded yet just became traversable.
    elseif center.propagate_excluded
            and not center.propagate_traversable
            and unexcluded then
        if not have_adjacent_excluded then
            adjacent_excluded_dist = select(2,
                distance_map_adjacent_dist(pos, dist_map))
        end

        local dist = dist_map.excluded_map[pos.x][pos.y]
        local target_dist = adjacent_excluded_dist
            and adjacent_excluded_dist + 1 or nil
        if dist ~= target_dist then
            if dist then
                dist_map.excluded_map[pos.x][pos.y] = nil
            else
                dist_map.excluded_map[pos.x][pos.y] = target_dist
            end

            if not update_pos then
                update_pos = new_update_position(pos)
            end
            update_pos.propagate_excluded = true
        end
    end

    if update_pos then
        dist_map.queue_next[hash_position(update_pos)] = true
        table.insert(dist_map.queue, update_pos)
    end
end

function distance_map_propagate(dist_map)
    local ind = 1
    local count = ind
    if debug_channel("update") then
        dsay("Propagating distance map at "
            .. cell_string_from_map_position(dist_map.pos))
    end
    while ind <= #dist_map.queue do
        if COROUTINE_THROTTLE and count % 300 == 0 then
            if debug_channel("update") then
                dsay("Propagated block " .. tostring(count / 300)
                    .. " with " .. tostring(#dist_map.queue - ind)
                    .. " positions remaining")
            end
            coroutine.yield()
        end

        local center = dist_map.queue[ind]
        dist_map.queue_next[center.hash] = nil

        for pos in adjacent_iter(center) do
            distance_map_update_adjacent_pos(pos, center, dist_map)
        end

        ind = ind + 1
        count = ind
    end

    dist_map.queue = {}
end

function record_cell_item(name, cell)
    if not item_map_positions[name] then
        item_map_positions[name] = {}
    end

    item_map_positions[name][cell.hash] = cell.pos
end

function handle_item_searches(cell)
    -- Don't do an expensive iteration over all items if we don't have an
    -- active search.
    if table_is_empty(item_searches) then
        return
    end

    local floor_items = items.get_items_at(cell.los_pos.x, cell.los_pos.y)
    if not floor_items then
        return
    end

    for _, it in ipairs(floor_items) do
        local name = it:name()
        if item_searches[name] then
            item_map_positions[name] = cell.pos
            item_searches[name] = nil

            if table_is_empty(item_searches) then
                return
            end
        end
    end
end

function new_update_position(pos)
    return {
        x = pos.x,
        y = pos.y,
        hash = hash_position(pos),
        propagate_traversable = false,
        propagate_untraversable = false,
        propagate_excluded = false,
        propagate_unexcluded = false
    }
end

function distance_map_update_position(pos, dist_map)
    if not (dist_map.radius
            and supdist(position_difference(dist_map.pos, pos))
                > dist_map.radius) then
        return
    end

    local traversable = map_is_traversable_at(pos)
    local unexcluded = map_is_unexcluded_at(pos)
    local dist, excluded_dist, update_pos
    local have_adjacent = false
    -- If we're traversable and don't have a map distance, we just became
    -- traversable, so update the map distance from adjacent squares.
    if traversable and not dist_map.map[pos.x][pos.y] then
        dist, excluded_dist = distance_map_adjacent_dist(pos, dist_map)
        have_adjacent = true
        if dist then
            dist_map.map[pos.x][pos.y] = dist + 1
            update_pos = new_update_position(pos)
            update_pos.propagate_traversable = true
        end
    -- If we're not traversable yet have a map distance, we just became
    -- untraversable, so nil both map distances.
    elseif not traversable and dist_map.map[pos.x][pos.y] then
        dist_map.map[pos.x][pos.y] = nil
        dist_map.excluded_map[pos.x][pos.y] = nil
        update_pos = new_update_position(pos)
        update_pos.propagate_untraversable = true
    end

    -- We're traversable and not excluded, yet have no excluded distance.
    if traversable
            and unexcluded
            and not dist_map.excluded_map[pos.x][pos.y] then
        if not have_adjacent then
            excluded_dist = select(2,
                distance_map_adjacent_dist(pos, dist_map))
        end

        if excluded_dist then
            dist_map.excluded_map[pos.x][pos.y] = excluded_dist + 1
            if not update_pos then
                update_pos = new_update_position(pos)
            end
            update_pos.propagate_unexcluded = true
        end
    -- We're excluded yet have an excluded distance, so we just became
    -- excluded.
    elseif excluded and dist_map.excluded_map[pos.x][pos.y] then
        dist_map.excluded_map[pos.x][pos.y] = nil
        if not update_pos then
            update_pos = new_update_position(pos)
        end
        update_pos.propagate_excluded = true
    end

    if update_pos then
        table.insert(dist_map.queue, update_pos)
    end
end

function has_exclusion_center_at(pos)
    local hash = hash_position(position_sum(global_pos, pos))
    return c_persist.exclusions[where] and c_persist.exclusions[where][hash]
end

--[[
Are the given map coordinates unexcluded according to the exclusion map cache?
@table pos The map position.
@treturn boolean True if coordinates are unexcluded, false otherwise.
--]]
function map_is_unexcluded_at(pos)
    return exclusion_map[pos.x][pos.y]
end

function update_map_cell_feature(cell, map_updated)
    -- These two features can appear spontaneously in an already seen LOS in
    -- the Abyss, so we handle them separately.
    if cell.feat == "abyssal_stair" then
        update_abyssal_stairs(cell.hash,
            { safe = unexcluded, los = los_state(cell.los_pos) })
        update_cell_feature_positions(cell)
        return
    end

    if cell.feat == "exit_abyss" then
        update_branch_stairs(where_branch, where_depth, "Abyss", DIR.UP,
            { safe = unexcluded, los = los_state(cell.los_pos) })
        update_cell_feature_positions(cell)
        return
    end

    if not map_updated then
        return
    end

    local dir, num = stone_stairs_type(cell.feat)
    if dir then
        update_stone_stairs(where_branch, where_depth, dir, num,
            { safe = unexcluded, los = los_state(cell.los_pos) })
        update_cell_feature_positions(cell)

        if not distance_maps[cell.hash] then
            distance_maps[cell.hash] = distance_map_initialize(cell.pos)
        end

        return
    end

    local dir = escape_hatch_type(cell.feat)
    if dir then
        update_escape_hatch(where_branch, where_depth, dir, cell.hash,
            { safe = unexcluded, los = los_state(cell.los_pos) })
        update_cell_feature_positions(cell)
        return
    end

    local branch, dir = branch_stairs_type(cell.feat)
    if branch then
        update_branch_stairs(where_branch, where_depth, branch, dir,
            { safe = unexcluded, los = los_state(cell.los_pos) })
        update_cell_feature_positions(cell)
        return
    end

    if cell.feat == "transit_pandemonium" then
        update_pan_transit(cell.hash,
            { safe = unexcluded, los = los_state(cell.los_pos) })
        update_cell_feature_positions(cell)
        return
    end

    if cell.feat == "runelight" then
        local state = { safe = unexcluded, los = los_state(cell.los_pos) }
        update_runelight(cell.hash, state)

        update_cell_feature_positions(cell)
        return
    end

    local god = altar_god(cell.feat)
    if god then
        update_altar(where, god, los_state(cell.los_pos))
        update_cell_feature_positions(cell)
        return
    end
end

function update_map_at_cell(cell, queue, seen)
    if seen[cell.hash] then
        return
    end

    local map_updated = false
    local traversable = feature_is_traversable(cell.feat)
    if traversal_map[cell.pos.x][cell.pos.y] ~= traversable then
        traversal_map[cell.pos.x][cell.pos.y] = traversable
        map_updated = true
    end

    local unexcluded = not (view.in_known_map_bounds(cell.los_pos.x,
            cell.los_pos.y)
        and travel.is_excluded(cell.los_pos.x, cell.los_pos.y))
    if exclusion_map[cell.pos.x][cell.pos.y] ~= unexcluded then
        exclusion_map[cell.pos.x][cell.pos.y] = unexcluded
        map_updated = true
    end

    seen[cell.hash] = true

    update_map_cell_feature(cell, map_updated)

    if not map_updated then
        return
    end

    for pos in adjacent_iter(cell.los_pos) do
        local acell = cell_from_position(pos, true)
        if acell and not seen[acell.hash] then
            table.insert(queue, acell)
        end
    end
end

function update_map_at_cells(queue)
    local seen = {}
    local ind = 1
    local last = #queue
    local count = 1
    while ind <= last do
        if COROUTINE_THROTTLE and count % 1000 == 0 then
            if debug_channel("update") then
                dsay("Updated map in block " .. tostring(count / 1000)
                    .. " with " .. tostring(last - ind) .. " cells remaining")
            end
            coroutine.yield()
        end

        local cell = queue[ind]
        update_map_at_cell(cell, queue, seen)
        handle_item_searches(cell)

        count = ind
        ind = ind + 1
        last = #queue
    end
end

function update_distance_maps_at_cells(queue)
    for i, cell in ipairs(queue) do
        if COROUTINE_THROTTLE and i % 1000 == 0 then
            if debug_channel("update") then
                dsay("Updated distance maps in block " .. tostring(i / 1000)
                    .. " of " .. tostring(#queue) .. " map cells")
            end
            coroutine.yield()
        end

        for _, dist_map in pairs(distance_maps) do
            distance_map_update_position(cell.pos, dist_map)
        end
    end

    for _, dist_map in pairs(distance_maps) do
        distance_map_propagate(dist_map)
    end
end

function update_map(new_level, full_clear)
    local new_waypoint = update_waypoint()

    -- A new waypoint means a new instance of a portal, a new level in Pan, or
    -- that that our Abyssal area has shifted, so we expire data for the
    -- relevant features.
    if new_waypoint and level_is_temporary() then
        c_persist.autoexplore[where_branch] = AUTOEXP.NEEDED
        c_persist.branch_exits[where_branch] = {}
    end

    if new_waypoint and in_branch("Pan") then
        c_persist.pan_transits = {}
    end

    if in_branch("Abyss") then
        if new_waypoint then
            c_persist.abyssal_stairs = {}
            c_persist.runelights = {}
        end

        -- If previous_where is nil, we're resuming froma save and were already
        -- in the Abyss, hence we don't want to unset this.
        if new_level and previous_where then
            c_persist.sensed_abyssal_rune = false
        end

    end

    if new_waypoint or full_clear then
        clear_map_cache(cache_parity, full_clear)
    end

    if new_level or new_waypoint or full_clear then
        traversal_map = traversal_maps_cache[cache_parity]
        exclusion_map = exclusion_maps_cache[cache_parity]
        distance_maps = distance_maps_cache[cache_parity]
        feature_map_positions = feature_map_positions_cache[cache_parity]
        item_map_positions = item_map_positions_cache[cache_parity]
        map_mode_searches = map_mode_searches_cache[cache_parity]
    end

    if in_branch("Abyss")
            and not (c_persist.seen_items[where]
                and c_persist.seen_items[where][abyssal_rune]) then
-- XXX: Re-enable this when abyssal rune sensing works.
--              and not c_persist.sensed_abyssal_rune then
        item_map_positions[abyssal_rune] = nil
    end

    update_exclusions(new_waypoint)

    item_searches = {}
    if c_persist.seen_items[where] then
        for name, _ in pairs(c_persist.seen_items[where]) do
            if not item_map_positions[name] then
                item_searches[name] = true
            end
        end
    end

    local purged = {}
    for name, _ in pairs(item_map_positions) do
        if have_progression_item(name) then
            table.insert(purged, name)
        end
    end
    for name, _ in ipairs(purged) do
        item_map_positions[name] = nil
    end

    local cell_queue = {}
    for pos in square_iter(origin, los_radius, true) do
        local cell = cell_from_position(pos, true)
        if cell then
            table.insert(cell_queue, cell)
        end
    end
    update_map_at_cells(cell_queue)

    if get_map_runelight(global_pos) then
        local state = { los = FEAT_LOS.EXPLORED }
        update_runelight(hash_position(global_pos), state)
    end

    -- Any seen item for which we don't have an item position is unregistered.
    if c_persist.seen_items[where] then
        local seen_items = {}
        for name, _ in pairs(c_persist.seen_items[where]) do
            if item_map_positions[name] then
                seen_items[name] = true
            end
        end
        c_persist.seen_items[where] = seen_items
    end

    local removed_maps = {}
    for _, dist_map in pairs(distance_maps) do
        if not map_is_traversable_at(dist_map.pos) then
            table.insert(removed_maps, dist_map)
        end
    end
    for _, dist_map in ipairs(removed_maps) do
        distance_map_remove(dist_map)
    end

    update_distance_maps_at_cells(cell_queue)

    if map_mode_search_key then
        local feat = view.feature_at(0, 0)
        -- We assume we've landed on the next feature in our current "X<key>"
        -- cycle because the feature at our position uses that key.
        if feature_uses_map_key(map_mode_search_key, feat) then
            record_map_mode_search(map_mode_search_key, map_mode_search_hash,
                map_mode_search_count, hash_position(global_pos))
        end
        map_mode_search_key = nil
        map_mode_search_hash = nil
        map_mode_search_count = nil
    end

    update_transporters()
end

function cell_from_position(pos, no_unseen)
    local feat = view.feature_at(pos.x, pos.y)
    if no_unseen and feat == "unseen" then
        return
    end

    local cell = {}
    cell.los_pos = pos
    cell.feat = feat
    cell.pos = position_sum(global_pos, pos)
    cell.hash = hash_position(cell.pos)
    return cell
end

function get_distance_map(pos, radius)
    local hash = hash_position(pos)
    if not distance_maps[hash] then
        distance_maps[hash] = distance_map_initialize(pos, radius)
        distance_map_propagate(distance_maps[hash])
    end
    return distance_maps[hash]
end

function get_feature_map_positions(feats, radius)
    local positions = {}
    local features = {}
    for _, feat in ipairs(feats) do
        if feature_map_positions[feat] then
            for _, pos in pairs(feature_map_positions[feat]) do
                table.insert(positions, pos)
                table.insert(features, feat)
            end
        end
    end
    if #positions > 0 then
        return positions, features
    end
end

function get_item_map_positions(item_names, radius)
    local positions = {}
    local found_items = {}
    for _, name in ipairs(item_names) do
        if item_map_positions[name] then
            table.insert(positions, item_map_positions[name])
            table.insert(found_items, name)
        end
    end
    if #positions > 0 then
        return positions, found_items
    end

    positions, found_items = find_items(item_names, radius)

-- XXX: Re-enable this when abyssal rune sensing works.
--  -- If we've searched the map for the abyssal rune and not found it, unset
--  -- our sensing of the rune.
--  if in_branch("Abyss")
--          and util.contains(item_names, abyssal_rune)
--          and not util.contains(found_items, rune) then
--      c_persist.sensed_abyssal_rune = false
--  end

    return positions, found_items
end

function update_cell_feature_positions(cell)
    if not feature_map_positions[cell.feat] then
        feature_map_positions[cell.feat] = {}
    end

    if not feature_map_positions[cell.feat][cell.hash] then
        feature_map_positions[cell.feat][cell.hash] = cell.pos
    end
end

function remove_exclusions(record_only)
    if not record_only and c_persist.exclusions[where] then
        for hash, _ in pairs(c_persist.exclusions[where]) do
            local pos = position_difference(unhash_position(hash), global_pos)
            if view.in_known_map_bounds(pos.x, pos.y) then
                if debug_channel("combat") then
                    dsay("Unexcluding position "
                        .. cell_string_from_map_position(pos))
                end

                travel.del_exclude(pos.x, pos.y)
            elseif debug_channel("combat") then
                dsay("Ignoring out of bounds exclusion coordinates "
                    .. pos_string(pos))
            end
        end
    end

    c_persist.exclusions[where] = {}
end

function exclude_position(pos)
    if debug_channel("map") then
        local desc
        local mons = monster_map[pos.x][pos.y]
        if mons then
            desc = mons:name()
        else
            desc = view.feature_at(pos.x, pos.y)
        end
        dsay("Excluding " .. desc .. " at " .. pos_string(pos))
    end

    if not c_persist.exclusions[where] then
        c_persist.exclusions[where] = {}
    end

    local hash = hash_position(position_sum(global_pos, pos))
    c_persist.exclusions[where][hash] = true
    travel.set_exclude(pos.x, pos.y)
end

function update_exclusions(new_waypoint)
    if new_waypoint then
        remove_exclusions()
    end

    -- Unreachable monsters that we can't ranged attack get excluded
    -- unconditionally.
    local auto_exclude = {}
    local have_ranged = best_missile()
    local have_temp_flight = find_item("potion", "flight")
    for _, enemy in ipairs(enemy_list) do
        if not has_exclusion_center_at(enemy:pos())
                and not enemy:is_summoned()
                -- We need to at least see all cells adjacent to them to be
                -- so our movement evaluation is reasonably correct.
                and enemy:adjacent_cells_known()
                -- They won't move into our melee range...
                and not enemy:can_move_to_player_melee()
                -- ...we can't move into melee range...
                and not enemy:player_has_path_to(have_temp_flight)
                -- ... and we already see that we can't target them with a
                -- ranged attack.
                and not (have_ranged and enemy:have_line_of_fire()) then
            table.insert(auto_exclude, enemy:pos())
        end
    end
    for _, pos in ipairs(auto_exclude) do
        exclude_position(pos)
    end

    -- We only exclude monsters when we have no incoming melee. Incoming melee
    -- is satisfied by any non-summoned monster that can either melee us now or
    -- is able to move into melee range given LOS terrain. We exclude summoned
    -- monsters so we can successfully exclude unreachable summoning monsters
    -- that can continuously make summons that are able to reach us.
    for _, enemy in ipairs(enemy_list) do
        if not enemy:is_summoned() and enemy:can_move_to_player_melee() then
            incoming_melee_turn = you.turns()
            return
        end
    end

    -- We want to exclude any unreachable monsters who get us to low HP while
    -- we're trying to kill them with ranged attacks. We additionally require
    -- that we've been at full HP since the last turn were we had reachable
    -- monsters. This way if we fight a mix of reachable and unreachable
    -- monsters and kill all the reachable ones but get to low HP, we'll
    -- retreat and heal up once before attempting to kill the unreachable ones.
    if full_hp_turn < incoming_melee_turn or not hp_is_low(50) then
        return
    end

    for _, enemy in ipairs(enemy_list) do
        if not enemy:is_summoned() then
            exclude_position(enemy:pos())
        end
    end
end

function want_to_use_transporters()
    return c_persist.autoexplore[where] == AUTOEXP.TRANSPORTER
        and (in_branch("Temple") or in_portal())
end

function update_transporters()
    transp_search = nil
    if want_to_use_transporters() then
        local feat = view.feature_at(0, 0)
        if feature_uses_map_key(">", feat) and transp_search_zone then
            if not transp_map[transp_search_zone] then
                transp_map[transp_search_zone] = {}
            end
            transp_map[transp_search_zone][transp_search_count] = transp_zone
            transp_search_zone = nil
            transp_search_count = nil
            if feat == "transporter" then
                transp_search = transp_zone
            end
        elseif branch_exit(where_branch) then
            transp_zone = 0
            transp_orient = false
        end
    end
end
