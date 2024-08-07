------------------
-- Level map data processing

-- Maximum map width. We use this as a general map radius that's guaranteed to
-- reach the entire map, since qw is never given absolute coordinates by crawl.
const.gxm = 80

-- Autoexplore state enum.
const.autoexplore = {
    "needed",
    "partial",
    "transporter",
    "runed_door",
    "full",
}

const.map_select = {
    "none",
    "excluded",
    "main",
    "both",
}

function main_map_selected(map_select)
    return map_select == const.map_select.main
        or map_select == const.map_select.both
end

function excluded_map_selected(map_select)
    return map_select == const.map_select.excluded
        or map_select == const.map_select.both
end

function update_waypoint(new_level)
    local place = where
    if in_portal() then
        place = "Portal"
    end

    local new_waypoint = false
    local waypoint_num = c_persist.waypoints[place]
    -- XXX: Hack to make Tomb hatch plans work. Re-create the waypoint each
    -- time we enter a level.
    if new_level and waypoint_num and in_branch("Tomb") then
        travel.set_waypoint(waypoint_num, 0, 0)
        new_waypoint = true
    elseif not waypoint_num then
        waypoint_num = c_persist.waypoint_count
        c_persist.waypoints[place] = waypoint_num
        c_persist.waypoint_count = waypoint_num + 1
        travel.set_waypoint(waypoint_num, 0, 0)
        new_waypoint = true
    end

    if not qw.map_pos then
        qw.map_pos = {}
    end
    qw.map_pos.x, qw.map_pos.y = travel.waypoint_delta(waypoint_num)

    -- The waypoint can become invalid due to entering a new Portal, a new Pan
    -- level, or due to an Abyss shift, etc.
    if not qw.map_pos.x then
        travel.set_waypoint(waypoint_num, 0, 0)
        qw.map_pos.x, qw.map_pos.y = travel.waypoint_delta(waypoint_num)
        new_waypoint = true
    end

    if new_level or new_waypoint then
        qw.move_destination = nil
        qw.enemy_map_memory = nil
        qw.last_enemy_map_memory = nil
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
    for x = -const.gxm, const.gxm do
        traversal_maps_cache[parity][x] = {}
    end

    exclusion_maps_cache[parity] = {}
    for x = -const.gxm, const.gxm do
        exclusion_maps_cache[parity][x] = {}
    end

    adjacent_floor_maps_cache[parity] = {}
    for x = -const.gxm, const.gxm do
        adjacent_floor_maps_cache[parity][x] = {}
    end
end

function find_features(feats, radius)
    if not radius then
        radius = const.gxm
    end

    local searches = {}
    for _, feat in ipairs(feats) do
        searches[feat] = true
    end

    local positions = {}
    local found_feats = {}
    local i = 1
    for pos in square_iter(const.origin, radius, true) do
        if qw.coroutine_throttle and i % 1000 == 0 then
            if debug_channel("throttle") then
                dsay("Searched features in block " .. tostring(i / 1000)
                    .. " of map positions")
            end

            qw.throttle = true
            coroutine.yield()
        end

        local feat = view.feature_at(pos.x, pos.y)
        if searches[feat] then
            if not feature_map_positions[feat] then
                feature_map_positions[feat] = {}
            end

            local gpos = position_sum(qw.map_pos, pos)
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

function find_map_items(item_names, radius)
    if not radius then
        radius = const.gxm
    end

    local searches = {}
    for _, name in ipairs(item_names) do
        searches[name] = true
    end

    local positions = {}
    local found_items = {}
    local i = 1
    for pos in square_iter(const.origin, radius, true) do
        if qw.coroutine_throttle and i % 1000 == 0 then
            if debug_channel("throttle") then
                dsay("Searched items in block " .. tostring(i / 1000)
                    .. " of map positions")
            end

            qw.throttle = true
            coroutine.yield()
        end

        local floor_items = items.get_items_at(pos.x, pos.y)
        if floor_items then
            for _, it in ipairs(floor_items) do
                local name = it.name()
                if searches[name] then
                    local map_pos = position_sum(qw.map_pos, pos)
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

function distance_map_initialize_maps(dist_map, excluded_only)
    if not excluded_only then
        dist_map.map = {}
        for x = -const.gxm, const.gxm do
            dist_map.map[x] = {}
        end
        dist_map.map[dist_map.pos.x][dist_map.pos.y] = 0
    end

    dist_map.excluded_map = {}
    for x = -const.gxm, const.gxm do
        dist_map.excluded_map[x] = {}
    end
    dist_map.excluded_map[dist_map.pos.x][dist_map.pos.y] =
        map_is_unexcluded_at(dist_map.pos) and 0 or nil
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

function is_traversable_at(pos)
    local gpos = position_sum(qw.map_pos, pos)
    return traversal_map[gpos.x][gpos.y]
end

function map_is_traversable_at(pos)
    return traversal_map[pos.x][pos.y]
end

function map_is_unseen_at(pos)
    return traversal_map[pos.x][pos.y] == nil
end

function distance_map_adjacent_dist(pos, dist_map, map_select)
    local best_dist, best_excluded_dist
    local main_selected = main_map_selected(map_select)
    local excluded_selected = excluded_map_selected(map_select)
    for pos in adjacent_iter(pos) do
        if map_is_traversable_at(pos) then
            local dist
            if main_selected then
                dist = dist_map.map[pos.x][pos.y]
                if dist and (not best_dist or best_dist > dist) then
                    best_dist = dist
                end
            end

            if excluded_selected then
                dist = dist_map.excluded_map[pos.x][pos.y]
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
    local center_dist = dist_map.map[center.x][center.y]
    local dist = dist_map.map[pos.x][pos.y]
    if not center.excluded_only
            and center_dist
            and (not dist or dist > center_dist + 1) then
        dist_map.map[pos.x][pos.y] = center_dist + 1

        update_pos = new_update_position(pos)
    end

    center_dist = dist_map.excluded_map[center.x][center.y]
    dist = dist_map.excluded_map[pos.x][pos.y]
    if map_is_unexcluded_at(pos)
            and center_dist
            and (not dist or dist > center_dist + 1) then
        dist_map.excluded_map[pos.x][pos.y] = center_dist + 1

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
            .. " with " .. tostring(#dist_map.queue) .. " update positions")
    end

    local ind = 1
    local count = ind
    while ind <= #dist_map.queue do
        if qw.coroutine_throttle and count % 300 == 0 then
            if debug_channel("throttle") then
                dsay("Propagated block " .. tostring(count / 300)
                    .. " with " .. tostring(#dist_map.queue - ind)
                    .. " positions remaining")
            end

            qw.throttle = true
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
        local name = it.name()
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
    -- If we're traversable and don't have a map distance, we just became
    -- traversable, so update the map distance from adjacent squares.
    if main_map_selected(map_select)
            and traversable
            and not dist_map.map[pos.x][pos.y] then
        dist, excluded_dist = distance_map_adjacent_dist(pos, dist_map,
            map_select)
        have_adjacent = true
        if dist then
            dist_map.map[pos.x][pos.y] = dist + 1
            update_pos = new_update_position(pos)
        end
    end

    -- We're traversable and not excluded, yet have no excluded distance.
    if excluded_map_selected(map_select)
            and traversable
            and map_is_unexcluded_at(pos)
            and not dist_map.excluded_map[pos.x][pos.y] then
        if not have_adjacent then
            excluded_dist = distance_map_adjacent_dist(pos, dist_map,
                const.map_select.excluded)
        end

        if excluded_dist then
            dist_map.excluded_map[pos.x][pos.y] = excluded_dist + 1
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

function has_exclusion_center_at(pos)
    local hash = hash_position(position_sum(qw.map_pos, pos))
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

function unexcluded_at(pos)
    return map_is_unexcluded_at(position_sum(qw.map_pos, pos))
end

function update_feature(branch, depth, feat, hash, state)
    local dir, num = stone_stairs_type(feat)
    if dir then
        update_stone_stairs(branch, depth, dir, num, state)
        return
    end

    if feat == "abyssal_stair" then
        update_abyssal_stairs(hash, state)
        return
    end

    local dest_branch, dir = branch_stairs_type(feat)
    if dest_branch then
        update_branch_stairs(branch, depth, dest_branch, dir, state)
        return
    end

    local dir = escape_hatch_type(feat)
    if dir then
        update_escape_hatch(branch, depth, dir, hash, state)
        return
    end

    if feat == "transit_pandemonium" then
        update_pan_transit(hash, state)
        return
    end

    local god = altar_god(feat)
    if god then
        update_altar(god, make_level(branch, depth), hash, state)
        return
    end
end

local state_features = {}
function feature_has_map_state(feat)
    local has_state = state_features[feat]
    if has_state == nil then
        has_state = stone_stairs_type(feat)
            or feat == "abyssal_stair"
            or branch_stairs_type(feat)
            or escape_hatch_type(feat)
            or feat == "transit_pandemonium"
            or altar_god(feat)
        state_features[feat] = has_state
    end

    return has_state
end

function expire_cell_portal(cell)
    for feat, positions in pairs(feature_map_positions) do
        local branch = branch_stairs_type(feat)
        if branch and is_portal_branch(branch) then
            for hash, _ in pairs(positions) do
                if cell.hash == hash then
                    remove_portal(where, branch)
                    return
                end
            end
        end
    end
end

function update_cell_feature(cell)
    if cell.feat == "expired_portal" then
        expire_cell_portal(cell)
    elseif not qw.have_slimy_walls and cell.feat == "slimy_wall" then
        qw.have_slimy_walls = true
    end

    local has_state = feature_has_map_state(cell.feat)
    if cell.feat == "runelight" or has_state then
        if not feature_map_positions[cell.feat] then
            feature_map_positions[cell.feat] = {}
        end
        if not feature_map_positions[cell.feat][cell.hash] then
            feature_map_positions[cell.feat][cell.hash] = cell.pos
        end
    end

    if not has_state then
        return
    end

    local enemies = assess_enemies(const.duration.ignore)
    local feat_state = feature_state(cell.los_pos)
    update_feature(where_branch, where_depth, cell.feat, cell.hash,
        { safe = exclusion_map[cell.pos.x][cell.pos.y], feat = feat_state,
            threat = enemies.threat })

    if feat_state < const.explore.reachable then
        check_reachable_features[cell.feat] = true
    end
end

function update_map_at_cell(cell, queue, seen)
    local map_reset = const.map_select.none

    if seen[cell.hash] then
        return map_reset
    end

    local map_updated = false
    local old_traversable = traversal_map[cell.pos.x][cell.pos.y]
    local cur_traversable = feature_is_traversable(cell.feat)
    if old_traversable ~= cur_traversable then
        traversal_map[cell.pos.x][cell.pos.y] = cur_traversable
        -- A cell went from traversable to untraversable, so any distance maps
        -- need a full reset.
        if old_traversable and not cur_traversable then
            map_reset = const.map_select.both
        end
        map_updated = true
    end

    local old_unexcluded = exclusion_map[cell.pos.x][cell.pos.y]
    local cur_unexcluded =
        not (view.in_known_map_bounds(cell.los_pos.x, cell.los_pos.y)
            and travel.is_excluded(cell.los_pos.x, cell.los_pos.y))
    if cur_traversable and old_unexcluded ~= cur_unexcluded then
        exclusion_map[cell.pos.x][cell.pos.y] = cur_unexcluded
        -- A traversable cell went from unexcluded to excluded, so the excluded
        -- maps of all distance maps need a reset.
        if old_unexcluded
                and not unexcluded
                and map_reset < const.map_select.both then
            map_reset = const.map_select.excluded
        end
        map_updated = true
    end

    update_cell_feature(cell)
    seen[cell.hash] = true

    if not map_updated then
        return map_reset
    end

    for pos in adjacent_iter(cell.los_pos) do
        local acell = cell_from_position(pos, true)
        if acell and not seen[acell.hash] then
            table.insert(queue, acell)
        end
    end

    return map_reset
end

function update_map_cells()
    local queue = {}
    for pos in square_iter(const.origin, qw.los_radius, true) do
        local cell = cell_from_position(pos, true)
        if cell then
            table.insert(queue, cell)
        end
    end

    local seen = {}
    local ind = 1
    local count = 1
    local map_reset = const.map_select.none
    while ind <= #queue do
        if qw.coroutine_throttle and count % 1000 == 0 then
            if debug_channel("throttle") then
                dsay("Updated map in block " .. tostring(count / 1000)
                    .. " with " .. tostring(#queue - ind) .. " cells remaining")
            end

            qw.throttle = true
            coroutine.yield()
        end

        local cell = queue[ind]
        local cell_map_reset = update_map_at_cell(cell, queue, seen)
        if cell_map_reset > map_reset then
            map_reset = cell_map_reset
        end

        handle_item_searches(cell)

        count = ind
        ind = ind + 1
    end

    return queue, map_reset
end

function update_distance_maps_at_cells(queue, map_select)
    for i, cell in ipairs(queue) do
        if qw.coroutine_throttle and i % 1000 == 0 then
            if debug_channel("throttle") then
                dsay("Updated distance maps in block " .. tostring(i / 1000)
                    .. " with " .. tostring(#queue - i) .. " cells remaining")
            end

            qw.throttle = true
            coroutine.yield()
        end

        for _, dist_map in pairs(distance_maps) do
            distance_map_update_position(cell.pos, dist_map, map_select)
        end
    end
end

function reset_c_persist(new_waypoint, new_level)
    -- A new waypoint means certain features that need to be identified by
    -- their global coordinates have to be erased.
    if new_waypoint then
        c_persist.up_hatches[where] = nil
        c_persist.down_hatches[where] = nil

        for god, _ in pairs(c_persist.altars) do
            c_persist.altars[god][where] = nil
        end
    end

    if new_waypoint and branch_is_temporary(where_branch) then
        c_persist.autoexplore[where_branch] = const.autoexplore.needed
        c_persist.branch_exits[where_branch] = {}
    end

    -- Certain branches and portals like Bazaars can be entered multiple times,
    -- so we need to clear their data immediately after leaving.
    if new_level then
        prev_branch = parse_level_range(previous_where)
        if prev_branch and branch_is_temporary(prev_branch) then
            c_persist.autoexplore[prev_branch] = const.autoexplore.needed
            c_persist.branch_exits[prev_branch] = {}
        end
    end

    if in_branch("Abyss") then
        if new_waypoint then
            c_persist.abyssal_stairs = {}
        end

        if new_level then
            c_persist.sense_abyssal_rune = false
        end
    end

    if new_waypoint and in_branch("Pan") then
        c_persist.pan_transits = {}
    end
end

function reset_map_cache(new_level, full_clear, new_waypoint)
    if new_waypoint or full_clear then
        clear_map_cache(cache_parity, full_clear)
    end

    if not previous_where or new_level or new_waypoint or full_clear then
        traversal_map = traversal_maps_cache[cache_parity]
        exclusion_map = exclusion_maps_cache[cache_parity]
        adjacent_floor_map = adjacent_floor_maps_cache[cache_parity]
        distance_maps = distance_maps_cache[cache_parity]
        feature_map_positions = feature_map_positions_cache[cache_parity]
        item_map_positions = item_map_positions_cache[cache_parity]
        map_mode_searches = map_mode_searches_cache[cache_parity]
    end
end

function reset_item_tracking()
    if in_branch("Abyss") then
        local rune = branch_runes(where_branch, true)[1]
        if not (c_persist.seen_items[where]
                    and c_persist.seen_items[where][rune])
                and not c_persist.sense_abyssal_rune then
            item_map_positions[rune] = nil
        end
    end

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
        if have_quest_item(name) then
            table.insert(purged, name)
        end
    end
    for name, _ in ipairs(purged) do
        item_map_positions[name] = nil
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

function update_seen_items()
    if not c_persist.seen_items[where] then
        return
    end

    -- Any seen item for which we don't have an item position is unregistered.
    local seen_items = {}
    for name, _ in pairs(c_persist.seen_items[where]) do
        if item_map_positions[name] then
            seen_items[name] = true
        end
    end
    c_persist.seen_items[where] = seen_items
end

function update_map_mode_search()
    if not map_mode_search_key then
        return
    end

    local feat = view.feature_at(0, 0)
    -- We assume we've landed on the next feature in our current "X<key>"
    -- cycle because the feature at our position uses that key.
    if feature_uses_map_key(map_mode_search_key, feat) then
        record_map_mode_search(map_mode_search_key, map_mode_search_hash,
            map_mode_search_count, hash_position(qw.map_pos))
    end
    map_mode_search_key = nil
    map_mode_search_hash = nil
    map_mode_search_count = nil
end

function update_adjacent_floor(queue)
    for _, cell in ipairs(queue) do
        if map_is_traversable_at(cell.pos) then
            local floor_count = 0
            for pos in adjacent_iter(cell.los_pos) do
                if not is_solid_at(pos, true) then
                    floor_count = floor_count + 1
                end
            end
            adjacent_floor_map[cell.pos.x][cell.pos.y] = floor_count
        end
    end
end

function update_map(new_level, full_clear)
    local new_waypoint = update_waypoint(new_level)

    reset_c_persist(new_waypoint, new_level)
    reset_map_cache(new_level, full_clear, new_waypoint)
    reset_item_tracking()

    update_exclusions(new_waypoint)

    if new_level then
        qw.have_slimy_walls = false
    end

    local cell_queue, map_reset = update_map_cells()
    update_adjacent_floor(cell_queue)

    update_seen_items()

    update_distance_maps(cell_queue, map_reset)

    update_map_mode_search()
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
    cell.pos = position_sum(qw.map_pos, pos)
    cell.hash = hash_position(cell.pos)
    return cell
end

function get_distance_map(pos, permanent, radius)
    local hash = hash_position(pos)
    if not distance_maps[hash] then
        distance_maps[hash] = distance_map_initialize(pos, permanent, radius)
        distance_map_propagate(distance_maps[hash])
    end
    return distance_maps[hash]
end

function get_feature_map_positions(feats)
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

    positions, found_items = find_map_items(item_names, radius)

    -- If we've searched the map for the abyssal rune and not found it, unset
    -- our sensing of the rune.
    if in_branch("Abyss") then
        local rune = branch_runes(where_branch, true)[1]
        if util.contains(item_names, rune)
                and not util.contains(found_items, rune) then
            c_persist.sense_abyssal_rune = false
        end
    end

    if #positions > 0 then
        return positions, found_items
    end
end

function remove_exclusions(record_only)
    if record_only or not c_persist.exclusions[where] then
        c_persist.exclusions[where] = nil
        return
    end

    for hash, _ in pairs(c_persist.exclusions[where]) do
        local pos = position_difference(unhash_position(hash), qw.map_pos)
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
    c_persist.exclusions[where] = nil
end

function exclude_position(pos)
    if debug_channel("map") then
        local desc
        local mons = get_monster_at(pos)
        if mons then
            desc = mons:name()
        else
            desc = view.feature_at(pos.x, pos.y)
        end
        dsay("Excluding " .. desc .. " at " .. pos_string(pos))
    end

    local hash = hash_position(position_sum(qw.map_pos, pos))
    if not c_persist.exclusions[where] then
        c_persist.exclusions[where] = {}
    end
    c_persist.exclusions[where][hash] = true

    travel.set_exclude(pos.x, pos.y)
end

function level_has_exclusions(branch, depth)
    return c_persist.exclusions[make_level(branch, depth)]
end

function update_exclusions(new_waypoint)
    if new_waypoint then
        remove_exclusions()
    end

    -- We're unlikely to be able to run away when mesmerised.
    if you.mesmerised() then
        return
    end

    -- Monsters we can't reach via melee or ranged attack that also can't move
    -- to our melee range get excluded immediately.
    local auto_exclude = {}
    local ranged_attack = get_ranged_attack()
    for _, enemy in ipairs(qw.enemy_list) do
        if not has_exclusion_center_at(enemy:pos())
                -- No excluding safe monsters.
                and not enemy:is_safe()
                -- No excluding temporary monsters.
                and not enemy:is_summoned()
                -- We need to at least see all cells adjacent to them to be
                -- so our movement evaluation is reasonably correct.
                and enemy:adjacent_cells_known()
                -- We can't move into melee range...
                and not enemy:player_has_path_to_melee()
                -- ... they can't move to where we could melee them
                and not enemy:player_can_wait_for_melee()
                -- ... and we can't target them with a ranged attack
                and not (ranged_attack
                    and enemy:player_has_line_of_fire(ranged_attack.index))
                -- ... and we know that we don't want to dig them out.
                and not enemy:should_dig_unreachable() then
            table.insert(auto_exclude, enemy:pos())
        end
    end
    if #auto_exclude > 0 then
        for _, pos in ipairs(auto_exclude) do
            exclude_position(pos)
        end
        return
    end

    -- We potentially exclude monsters that can't reach our position when we've
    -- tried to fight them from full HP. To make this assessment, we track the
    -- last turn a monster could reach us.
    for _, enemy in ipairs(qw.enemy_list) do
        if not enemy:is_summoned() and enemy:has_path_to_player() then
            qw.incoming_monsters_turn = you.turns()
            return
        end
    end

    -- If we've been trying to attack monsters that can't reach our position
    -- and get to low HP, we wan't to exclude them and end the fight. We
    -- additionally require that we've been at full HP since the last turn were
    -- we had incoming monsters. This way if we fight a mix of some monsters
    -- that can reach us and some that can't, we'll deal with the monsters that
    -- can't only after finishing off the monsters that can and then resting to
    -- full HP.
    if qw.full_hp_turn > 0
            and qw.full_hp_turn >= qw.incoming_monsters_turn
            and hp_is_low(50) then
        for _, enemy in ipairs(qw.enemy_list) do
            if not enemy:is_summoned() then
                exclude_position(enemy:pos())
            end
        end
    end
end

function want_to_use_transporters()
    return c_persist.autoexplore[where] == const.autoexplore.transporter
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
