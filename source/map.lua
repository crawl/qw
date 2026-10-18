------------------
-- Level map data processing

-- For a level's autoexplore state.
const.autoexplore = enum({
    "needed",
    "partial",
    "transporter",
    "runed_door",
    "full",
})

const.trap_scores = {
    shaft = 0,
    trap_teleport = 1,
    trap_teleport_permanent = 1,
    web = 1,
    trap_harlequin = 2,
    trap_archmage = 2,
    trap_net = 3,
    trap_dispersal = 3,
    trap_dispersal_inactive = 3,
    trap_tyrant = 3,
    trap_devourer = 3,
    trap_zot = 4,
    trap_alarm = 5,
    trap_pressure_plate = 5,
}

function map_trap_score_at(pos)
    return qw.trap_score_map[pos.hash]
end

function trap_score_at(pos)
    return map_trap_score_at(map_position(pos))
end

function update_waypoint(new_level, force)
    local place = where
    if in_portal() then
        place = "Portal"
    end

    local new_waypoint = false
    local waypoint_num = c_persist.waypoints[place]
    -- XXX: Hack to make Tomb hatch plans work. Re-create the waypoint each
    -- time we enter a level.
    if waypoint_num and new_level and (force or in_branch("Tomb")) then
        travel.set_waypoint(waypoint_num, 0, 0)
        new_waypoint = true
    elseif not waypoint_num then
        waypoint_num = c_persist.waypoint_count
        c_persist.waypoints[place] = waypoint_num
        c_persist.waypoint_count = waypoint_num + 1
        travel.set_waypoint(waypoint_num, 0, 0)
        new_waypoint = true
    end

    qw.map_pos = new_position(travel.waypoint_delta(waypoint_num))

    -- The waypoint can become invalid due to entering a new Portal, a new Pan
    -- level, or due to an Abyss shift, etc.
    if not qw.map_pos then
        travel.set_waypoint(waypoint_num, 0, 0)
        qw.map_pos = new_position(0, 0)
        new_waypoint = true
    end

    if new_level or new_waypoint then
        qw.move_destination = nil
        qw.enemy_map_memory = nil
        qw.last_enemy_map_memory = nil
    end

    return new_waypoint
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
        local floor_items = items.get_items_at(pos.x, pos.y)
        if floor_items then
            for _, it in ipairs(floor_items) do
                local name = it.name()
                if searches[name] then
                    local map_pos = map_position(pos)
                    qw.item_positions[name] = map_pos
                    table.insert(positions, map_pos)
                    table.insert(found_items, name)

                    searches[name] = nil
                    if table_is_empty(searches) then
                        return positions, found_items
                    end
                end
            end
        end

        if qw.coroutine_throttle and i % 1000 == 0 then
            if debug_channel("map-all") then
                dsayf("Searched %d map positions for items", i)
            end

            coroutine.yield()
        end

        i = i + 1
    end

    return positions, found_items
end

function is_traversable_at(pos)
    return map_is_traversable_at(map_position(pos))
end

function map_is_traversable_at(pos)
    return qw.traversable_map[pos.hash]
end

function map_is_unseen_at(pos)
    return qw.traversable_map[pos.hash] == nil
end

function update_item_search_from_cell(cell)
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
            qw.item_positions[name] = cell.map_pos
            item_searches[name] = nil

            if table_is_empty(item_searches) then
                return
            end
        end
    end
end

function map_has_exclusion_at(pos)
    return c_persist.exclusions[where]
        and c_persist.exclusions[where][pos.hash]
end

--[[
Are the given map coordinates excluded according to the map cache?
@table pos The map position.
@treturn boolean True if coordinates are excluded, false otherwise.
--]]
function map_is_excluded_at(pos)
    return qw.excluded_map[pos.hash]
end

function is_excluded_at(pos)
    return map_is_excluded_at(map_position(pos))
end

--[[
Is the terrain safe according to the safety map cache?
@table pos The map position.
@treturn boolean True if the terrain at pos is safe, false otherwise.
--]]
function map_feature_is_safe_at(pos)
    return qw.feature_safe_map[pos.hash]
end

--[[
Are the given map coordinates safe?
@table pos The map position.
@boolean no_monster If true, the position is considered unsafe whenever a
                    monster of any kind is present.
@treturn boolean True if position is safe, false otherwise.
--]]
function map_is_safe_at_func(pos, no_monster)
    if not map_feature_is_safe_at(pos) or map_is_excluded_at(pos) then
        return false
    end

    local los_pos = los_position(pos)
    if supdist(los_pos) > qw.los_radius then
        return true
    end

    if view.withheld(los_pos.x, los_pos.y)
            or not cloud_is_safe(view.cloud_at(los_pos.x, los_pos.y)) then
        return false
    end

    local mons = get_monster_at(los_pos)
    if mons then
        if no_monster then
            return false
        else
            return mons:player_can_swap()
        end
    else
        return true
    end
end

function map_is_safe_at(pos, no_monster)
    return turn_memo_args(map_is_safe_at_func, pos, no_monster)
end

function is_safe_at(pos, no_monster)
    return map_is_safe_at(map_position(pos), no_monster)
end

function get_feature_state(branch, depth, feat, map_pos)
    local state = get_stairs_state(branch, depth, feat)
    if state then
        return state
    end

    local dir = escape_hatch_type(feat)
    if dir then
        return get_escape_hatch_state(branch, depth, dir, map_pos)
    end

    if feat == "abyssal_stair" then
        return c_persist.abyssal_stairs[map_pos.hash]
    end

    if feat == "transit_pandemonium" then
        return c_persist.pan_transits[map_pos.hash]
    end

    local god = altar_god(feat)
    if god then
        return get_altar_state(god, branch, depth, map_pos)
    end
end

function update_feature_state(branch, depth, feat, map_pos, state, force)
    local dir, num = stone_stairs_type(feat)
    if dir then
        update_stone_stairs_state(branch, depth, dir, num, state, force)
        return
    end

    local dest_branch, dir = branch_stairs_type(feat)
    if dest_branch then
        update_branch_stairs_state(branch, depth, dest_branch, dir, state,
            force)
        return
    end

    if feat == "abyssal_stair" then
        update_abyssal_stairs_state(map_pos, state, force)
        return
    end

    local dir = escape_hatch_type(feat)
    if dir then
        update_escape_hatch_state(branch, depth, dir, map_pos, state, force)
        return
    end

    if feat == "transit_pandemonium" then
        update_pan_transit_state(map_pos, state, force)
        return
    end

    local god = altar_god(feat)
    if god then
        update_altar_state(god, branch, depth, map_pos, state, force)
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

function expire_portal_from_cell(cell)
    for feat, positions in pairs(qw.feature_positions) do
        local branch = branch_stairs_type(feat)
        if branch and is_portal_branch(branch) then
            for hash, _ in pairs(positions) do
                if cell.map_pos.hash == hash then
                    remove_portal(where, branch)
                    return
                end
            end
        end
    end
end

function update_trap_from_cell(cell)
    local new_score = const.trap_scores[cell.feat]
    if not new_score then
        new_score = 0
    end

    local old_score = const.trap_scores[cell.old_feat]
    if not old_score then
        old_score = 0
    end

    if old_score == new_score then
        return
    end

    for pos in square_iter(cell.map_pos, qw.los_radius, true) do
        if map_is_traversable_at(pos)
                and map_cell_see_cell(pos, cell.map_pos) then
            local map_score = qw.trap_score_map[pos.hash]
            if not map_score then
                map_score = 0
            end

            local dist = position_distance(pos, cell.map_pos)
            qw.trap_score_map[pos.hash] = map_score
                + (qw.los_radius - dist + 1) * (new_score - old_score)
        end
    end
end

function update_feature_from_cell(cell)
    local feature_updated = false
    cell.old_feat = qw.feature_map[cell.map_pos.hash]
    local is_trap = feature_is_trap(cell.feat)
    if cell.old_feat ~= cell.feat then
        feature_updated = true
        qw.feature_map[cell.map_pos.hash] = cell.feat

        if cell.feat == "expired_portal" then
            expire_portal_from_cell(cell)
        elseif not qw.slimy_walls and cell.feat == "slimy_wall" then
            qw.slimy_walls = true
        end

        if is_trap or feature_is_trap(cell.old_feat) then
            table.insert(cell.queue.trap_cells, cell)
        end
    end

    local traversable = feature_is_traversable(cell.feat)
    qw.traversable_map[cell.map_pos.hash] = traversable
    -- This cell may never be in LOS of a trap, so we 0-initialize it here.
    if traversable and not qw.trap_score_map[cell.map_pos.hash] then
        qw.trap_score_map[cell.map_pos.hash] = 0
    end

    local is_excluded = travel.is_excluded(cell.los_pos.x,
        cell.los_pos.y)
    qw.excluded_map[cell.map_pos.hash] = is_excluded
    qw.feature_safe_map[cell.map_pos.hash] = traversable
        and not (is_excluded or is_trap)

    if feature_has_map_state(cell.feat) then
        table.insert(cell.queue.feature_state_cells, cell)
    end

    if not c_persist.zot5.entry_pos
            and at_branch_end("Zot")
            and cell.feat == "granite_statue" then
        table.insert(cell.queue.zot5_cells, cell)
    end

    update_item_search_from_cell(cell)

    if cell.queue.no_propagate or not feature_updated then
        return
    end

    for pos in adjacent_iter(cell.los_pos) do
        local acell = cell_from_position(pos, true)
        if not acell or cell.queue.update_set[acell.map_pos.hash] then
            goto continue
        end

        acell.queue = cell.queue
        table.insert(cell.queue.update_cells, acell)
        cell.queue.update_set[acell.map_pos.hash] = acell

        ::continue::
    end
end

function update_map_features()
    local cells = qw.map_queue.update_cells
    local ind = 1
    -- This list can grow as we iterate, hence we don't use an iterator.
    while ind <= #cells do
        update_feature_from_cell(cells[ind])

        if qw.coroutine_throttle and ind % 1000 == 0 then
            if debug_channel("map-all") then
                dsayf("Updated map features in block %d with %d cells"
                        .. " remaining", ind / 1000, #cells - ind)
            end

            coroutine.yield()
        end

        ind = ind + 1
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

local cache_tables = { "feature_map", "traversable_map", "excluded_map",
    "feature_safe_map", "trap_score_map", "feature_positions",
    "item_positions", "distance_maps" }
function clear_map_cache(slot)
    if debug_channel("map") then
        dsay("Clearing map cache for slot " .. slot)
    end

    qw.cache[slot] = {}
    for _, t in ipairs(cache_tables) do
        qw.cache[slot][t] = {}
    end
end

function load_map_cache(new_level, clear_cache)
    if clear_cache then
        clear_map_cache(qw.cache.slot)
    end

    if new_level or clear_cache then
        -- Load these tables from cache at the given slot into the main qw
        -- table for easier access. TODO: Make cache a class so we don't have
        -- to do this.
        for _, t in ipairs(cache_tables) do
            qw[t] = qw.cache[qw.cache.slot][t]
        end
    end
end

function reset_item_tracking()
    if in_branch("Abyss") then
        local rune = branch_runes(where_branch, true)[1]
        if not (c_persist.seen_items[where]
                    and c_persist.seen_items[where][rune])
                and not c_persist.sense_abyssal_rune then
            qw.item_positions[rune] = nil
        end
    end

    item_searches = {}
    if c_persist.seen_items[where] then
        for name, _ in pairs(c_persist.seen_items[where]) do
            if not qw.item_positions[name] then
                item_searches[name] = true
            end
        end
    end

    local purged = {}
    for name, _ in pairs(qw.item_positions) do
        if have_quest_item(name) then
            table.insert(purged, name)
        end
    end
    for name, _ in ipairs(purged) do
        qw.item_positions[name] = nil
    end
end

function update_seen_items()
    if not c_persist.seen_items[where] then
        return
    end

    -- Any seen item for which we don't have an item position is unregistered.
    local seen_items = {}
    for name, _ in pairs(c_persist.seen_items[where]) do
        if qw.item_positions[name] then
            seen_items[name] = true
        end
    end
    c_persist.seen_items[where] = seen_items
end

function update_zot5_from_cell(cell)
    if debug_channel("map-all") then
        dsay("Checking Zot:5 features from " .. cell_string(cell))
    end

    local y_offset
    local pos = cell.los_pos
    if feature_at(position_coord_sum(pos, 0, 1)) == "stone_wall" then
        y_offset =  1
    elseif feature_at(position_coord_sum(pos, 0, -1)) == "stone_wall" then
        y_offset =  -1
    else
        return
    end
    if debug_channel("map-all") then
        dsay("Found y offset: " .. y_offset)
    end


    local x_offset
    if feature_at(position_coord_sum(pos, 1, y_offset)) == "stone_wall" then
        x_offset = 1
    elseif feature_at(position_coord_sum(pos, -1, y_offset))
            == "stone_wall" then
        x_offset = -1
    else
        return
    end
    if debug_channel("map-all") then
        dsay("Found x offset: " .. x_offset)
    end

    if feature_at(position_coord_sum(pos, 2 * x_offset, y_offset))
            ~= "permarock_wall" then
        return
    end

    local map_pos = cell.map_pos
    c_persist.zot5.entry_pos = position_coord_sum(map_pos, 21 * x_offset,
        -12 * y_offset)
    c_persist.zot5.orb_pos = position_coord_sum(map_pos, 21 * x_offset,
        9 * y_offset)

    if debug_channel("map-all") then
        dsay("Found Hall of Zot entry position "
            .. cell_string_from_map_position(c_persist.zot5.entry_pos)
            .. " and Orb position "
            .. cell_string_from_map_position(c_persist.zot5.orb_pos))
    end

    -- We want to fully autoexplore outside the Hall of Zot, unless the
    -- tesseracts activate first, so exclude the entry cell.
    if not c_persist.zot5.tesseracts_active then
        exclude_map_at(c_persist.zot5.entry_pos)
    end

    local hall1 = {
        tesseract_pos = position_coord_sum(map_pos, 0, 2 * y_offset ),
        chamber_pos = position_coord_sum(map_pos, 15 * x_offset, 9 * y_offset)
    }
    local hall2 = {
        tesseract_pos = position_coord_sum(map_pos, 42, 2 * y_offset),
        chamber_pos = position_coord_sum(map_pos, 27 * x_offset, 9 * y_offset)
    }
    c_persist.zot5.halls = { hall1, hall2 }

    if debug_channel("map-all") then
        dsay("Found first tesseract position: "
            .. cell_string_from_map_position(hall1.tesseract_pos)
            .. "; found first chamber position: "
            .. cell_string_from_map_position(hall1.chamber_pos))
        dsay("Found second tesseract position: "
            .. cell_string_from_map_position(hall2.tesseract_pos)
            .. "; found second chamber position: "
            .. cell_string_from_map_position(hall2.chamber_pos))
    end
end

-- Update any feature state information that requires the entire
-- feature map to be updated.
function update_feature_state_from_cell(cell)
    -- All features that have state have their positions
    -- recorded.
    if not qw.feature_positions[cell.feat] then
        qw.feature_positions[cell.feat] = {}
    end
    if not qw.feature_positions[cell.feat][cell.map_pos.hash] then
        qw.feature_positions[cell.feat][cell.map_pos.hash] = cell.map_pos
    end

    local enemies = assess_enemies(const.duration.ignore)
    update_feature_state(where_branch, where_depth, cell.feat, cell.map_pos,
        -- We don't care about non-permanent clouds and these features can
        -- never be traps, so checking for exclusions is enough.
        { safe = not map_is_excluded_at(cell.map_pos),
          explore = explore_state_at(cell.map_pos), threat = enemies.threat })
end

function finalize_map_features(queue)
    for _, cell in ipairs(qw.map_queue.trap_cells) do
        update_trap_from_cell(cell)
    end

    for _, cell in ipairs(qw.map_queue.feature_state_cells) do
        update_feature_state_from_cell(cell)
    end

    for _, cell in ipairs(qw.map_queue.zot5_cells) do
        update_zot5_from_cell(cell)
    end

    -- For all recorded feature positions, re-evaluate whether any unreachable
    -- ones have become reachable.
    for feat, positions in pairs(qw.feature_positions) do
        for _, pos in ipairs(positions) do
            local state = get_feature_state(where_branch, where_depth, feat,
                pos)
            if state and state.explore < const.explore.reachable
                    and map_is_reachable_at(pos) then
                update_feature_state(where_branch, where_depth, feat, pos,
                    { explore = const.explore.reachable })
            end
        end
    end
end

function update_map_queue(clear_cache)
    local queue = { update_cells = {}, update_set = {}, trap_cells = {},
        feature_state_cells = {}, zot5_cells = {} }
    local radius
    if clear_cache or qw.update_entire_map then
        radius = const.gxm
        queue.no_propagate = true
        qw.update_entire_map = false
    else
        radius = qw.los_radius
    end

    if debug_channel("map-all") then
        dsayf("Updating map queue with radius %d", radius)
    end

    local i = 1
    for pos in square_iter(const.origin, radius, true) do
        local cell = cell_from_position(pos, true, true)
        if not cell then
            goto continue
        end

        cell.queue = queue
        table.insert(queue.update_cells, cell)
        queue.update_set[cell.map_pos.hash] = cell

        if qw.coroutine_throttle and i % 1000 == 0 then
            if debug_channel("map-all") then
                dsayf("Queued %d map positions", i)
            end

            coroutine.yield()
        end

        i = i + 1

        ::continue::
    end

    qw.map_queue = queue
end

function update_map(new_level, clear_cache)
    local new_waypoint = update_waypoint(new_level)

    reset_c_persist(new_waypoint, new_level)
    -- For the Abyss or Tomb, new waypoints are repeatedly made on levels
    -- we've visited before, so we force clearing map cache in that case.
    load_map_cache(new_level, clear_cache or new_waypoint)
    reset_item_tracking()

    if new_level then
        qw.slimy_walls = false
    end

    update_map_queue(clear_cache)

    -- This first pass of the map update handles the feature and traversability
    -- data.
    update_map_features()
    update_transporters()
    update_seen_items()

    -- We must update the enemy list before possibly excluding any of them.
    update_monsters()
    update_map_exclusions(new_waypoint)

    finalize_map_features()
    expire_distance_maps()
end

function cell_from_position(pos, no_unseen, no_cache)
    local feat
    if no_cache then
        feat = view.feature_at(pos.x, pos.y)
    else
        feat = feature_at(pos, no_cache)
    end
    if no_unseen and feat == "unseen" then
        return
    end

    local cell = { los_pos = pos, feat = feat }
    if qw.map_pos then
        cell.map_pos = map_position(pos)
    end

    return cell
end

function get_feature_positions(feats)
    local positions = {}
    local features = {}
    for _, feat in ipairs(feats) do
        if qw.feature_positions[feat] then
            for _, pos in pairs(qw.feature_positions[feat]) do
                table.insert(positions, pos)
                table.insert(features, feat)
            end
        end
    end
    if #positions > 0 then
        return positions, features
    end
end

function get_item_positions(item_names, radius)
    local positions = {}
    local found_items = {}
    for _, name in ipairs(item_names) do
        if qw.item_positions[name] then
            table.insert(positions, qw.item_positions[name])
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

function exclude_at(pos, radius)
    if not radius then
        radius = qw.los_radius
    end

    if debug_channel("map") then
        dsay("Excluding " .. cell_string_from_position(pos))
    end

    local map_pos = map_position(pos)
    if not c_persist.exclusions[where] then
        c_persist.exclusions[where] = {}
    end
    c_persist.exclusions[where][map_pos.hash] = radius

    for epos in square_iter(map_pos, radius, true) do
        qw.excluded_map[epos.hash] = true
    end

    travel.set_exclude(pos.x, pos.y, radius)
end

function exclude_map_at(pos, radius)
    exclude_at(los_position(pos), radius)
end

function unexclude_at(pos)
    if debug_channel("map") then
        dsay("Unexcluding " .. cell_string_from_map_position(pos))
    end

    travel.del_exclude(pos.x, pos.y)

    local map_pos = map_position(pos)
    local radius = c_persist.exclusions[where][map_pos.hash]
    c_persist.exclusions[where][map_pos.hash] = nil

    -- Update exclusion data. Check all squares in the radius, since
    -- exclusions that overlapped this one might still exist.
    for epos in square_iter(pos, radius) do
        -- travel will error if given coordinates out of map bounds.
        if view.in_known_map_bounds(epos.x, epos.y) then
            qw.excluded_map[map_position(epos).hash] =
                travel.is_excluded(epos.x, epos.y)
        end
    end
end

function unexclude_map_at(pos)
    unexclude_at(los_position(pos))
end

function remove_exclusions(record_only)
    if record_only then
        c_persist.exclusions[where] = nil
        return
    end

    local exclusions = c_persist.exclusions[where]
    if not exclusions then
        return
    end

    for hash, _ in pairs(exclusions) do
        unexclude_map_at(position_from_hash(hash))
    end
end

function level_has_exclusions(branch, depth)
    local exc = c_persist.exclusions[make_level(branch, depth)]
    return exc and next(exc)
end

function update_map_exclusions(new_waypoint)
    if new_waypoint then
        remove_exclusions()
    end

    -- Once we've either autoexplored outside the Zot:5 vault or activated the
    -- tesseracts, it's time to enter the vault.
    if at_branch_end("Zot")
            and c_persist.zot5.entry_pos
            and map_has_exclusion_at(c_persist.zot5.entry_pos)
            and (explored_level(where_branch, where_depth)
                or c_persist.zot5.tesseracts_active) then
        unexclude_map_at(c_persist.zot5.entry_pos)
    end

    -- Monsters we can't reach via melee or ranged attack that also can't move
    -- to our melee range get excluded immediately.
    for _, enemy in ipairs(qw.enemy_list) do
        if not map_has_exclusion_at(enemy:map_pos())
                -- No excluding safe monsters.
                and not enemy:is_safe()
                -- No excluding temporary monsters.
                and not enemy:is_summoned()
                -- We need to at least see all cells adjacent to them to be
                -- so our movement evaluation is reasonably correct.
                and enemy:adjacent_cells_known()
                -- One of two main cases must be further satisfied before we
                -- exclude this monster.
                --
                -- (1) If we've gotten to low HP trying to attack monsters
                -- that can't reach our position. Specifically we require...
                -- ... that we have rested to full HP...
                and (qw.full_hp_turn > 0
                        -- ... since the turn we last had incoming monsters...
                        and qw.full_hp_turn >= qw.incoming_monsters_turn
                        -- ... and our HP is low.
                        and hp_is_low(50)
                    -- or (2) We have no way of attacking the monster or using
                    -- a ranged attack and we don't want to dig them out.
                    -- Specifically we require...
                    -- ... that we can't move into melee range...
                    or not enemy:player_has_path_to_melee(true)
                        -- ... and they can't move into our melee range
                        and not enemy:player_can_wait_for_melee()
                        -- ... and we can't target them with a range attack
                        and not enemy:best_player_attack()
                        -- ... and we don't want to (or can't) dig them out.
                        and not enemy:should_dig_unreachable()) then
            exclude_at(enemy:pos())
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
        local feat = feature_at(const.origin)
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
