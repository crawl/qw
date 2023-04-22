------------------
-- Stair-related functions

-- Stair direction enum
DIR = { UP = -1, DOWN = 1 }

INF_DIST = 10000

upstairs_features = {
    "stone_stairs_up_i",
    "stone_stairs_up_ii",
    "stone_stairs_up_iii",
}

downstairs_features = {
    "stone_stairs_down_i",
    "stone_stairs_down_ii",
    "stone_stairs_down_iii",
}

--[[
Return a list of stair features on the given level and in the given direction.
This does include any exits from the given branch but not any entrances to
different branches. For downstairs, it does include features on temporary
levels like Abyss and Pan that lead to the "next" level in the branch.
--]]
function level_stairs_features(branch, depth, dir)
    local feats
    if dir == DIR.UP then
        if is_portal_branch(branch)
                or branch == "Abyss"
                or util.contains(hell_branches, branch)
                or depth == 1 then
            feats = { branch_exit(branch) }
        else
            feats = upstairs_features
        end
    elseif dir == DIR.DOWN then
        if branch == "Abyss" then
            feats = { "abyssal_stair" }
        elseif branch == "Pan" then
            feats = { "transit_pandemonium" }
        elseif util.contains(hell_branches, branch)
                and depth < branch_depth(branch)then
            feats = { downstairs_features[1] }
        elseif depth < branch_depth(branch) then
            feats = downstairs_features
        end
    end
    return feats
end

function stairs_state_string(state)
    return enum_string(state.los, FEAT_LOS) .. "/"
        .. (state.safe and "safe" or "unsafe")
end

function update_stone_stairs(branch, depth, dir, num, state, force)
    if not state.safe and not state.los then
        error("Undefined stairs state.")
    end

    local data
    if dir == DIR.DOWN then
        data = c_persist.downstairs
    else
        data = c_persist.upstairs
    end

    local level = make_level(branch, depth)
    if not data[level] then
        data[level] = {}
    end

    if not data[level][num] then
        data[level][num] = {}
    end

    local current = data[level][num]
    if current.safe == nil then
        current.safe = true
    end
    if current.los == nil then
        current.los = FEAT_LOS.NONE
    end

    if state.safe == nil then
        state.safe = current.safe
    end

    if state.los == nil then
        state.los = current.los
    end

    local los_changed = current.los < state.los
            or force and current.los ~= state.los
    if state.safe ~= current.safe or los_changed then
        if debug_channel("explore") then
            dsay("Updating stone " .. (dir == DIR.UP and "up" or "down")
                .. "stairs " .. num .. " on " .. level
                .. " from " .. stairs_state_string(current) .. " to "
                .. stairs_state_string(state))
        end

        current.safe = state.safe

        if los_changed and not force then
            current.los = state.los
            want_gameplan_update = true
        end
    end
end

function update_all_stone_stairs(branch, depth, dir, state, max_los)
    for i = 1, num_required_stairs(branch, depth, dir) do
        if not max_los
                or get_stone_stairs_state(branch, depth, dir, i).los
                    >= state.los then
            update_stone_stairs(branch, depth, dir, i, state, true)
        end
    end
end

function reset_stone_stairs(branch, depth, dir)
    update_all_stone_stairs(branch, depth, dir, { los = FEAT_LOS.REACHABLE },
        true)

    local level = make_level(branch, depth)
    if level == where then
        map_mode_searches[dir_key(dir)] = nil
    elseif level == previous_where then
        map_mode_searches_cache[3 - cache_parity][dir_key(dir)] = nil
    end

    if where ~= level then
        dsay("Resetting autoexplore of " .. lev, "explore")
        c_persist.autoexplore[lev] = AUTOEXP.NEEDED
    end
end

function get_stone_stairs_state(branch, depth, dir, num)
    local level = make_level(branch, depth)
    if dir == DIR.UP then
        if not c_persist.upstairs[level]
                or not c_persist.upstairs[level][num] then
            return { safe = true, los = FEAT_LOS.NONE }
        end

        return c_persist.upstairs[level][num]
    elseif dir == DIR.DOWN then
        if not c_persist.downstairs[level]
                or not c_persist.downstairs[level][num] then
            return { safe = true, los = FEAT_LOS.NONE }
        end

        return c_persist.downstairs[level][num]
    end
end

function num_required_stairs(branch, depth, dir)
    if dir == DIR.UP then
        if depth == 1
                or is_portal_branch(branch)
                or branch == "Tomb"
                or branch == "Abyss"
                or branch == "Pan"
                or util.contains(hell_branches, branch) then
            return 0
        else
            return 3
        end
    elseif dir == DIR.DOWN then
        if depth == branch_depth(branch)
                    or is_portal_branch(branch)
                    or branch == "Tomb"
                    or branch == "Abyss"
                    or branch == "Pan" then
            return 0
        elseif util.contains(hell_branches, branch) then
            return 1
        else
            return 3
        end
    end
end

function count_stairs(branch, depth, dir, los)
    local num_required = num_required_stairs(branch, depth, dir)
    if num_required == 0 then
        return 0
    end

    local num
    local count = 0
    for i = 1, num_required do
        num = "i"
        num = num:rep(i)
        if get_stone_stairs_state(branch, depth, dir, num).los >= los then
            count = count + 1
        end
    end
    return count
end

function have_all_stairs(branch, depth, dir, los)
    local num_required = num_required_stairs(branch, depth, dir)
    if num_required > 0 then
        local num
        for i = 1, num_required do
            num = "i"
            num = num:rep(i)
            if get_stone_stairs_state(branch, depth, dir, num).los < los then
                return false
            end
        end
    end

    return true
end

function update_branch_stairs(branch, depth, dest_branch, dir, state)
    if not state.safe and not state.los then
        error("Undefined branch stairs state.")
    end

    local data = dir == DIR.DOWN and c_persist.branch_entries
        or c_persist.branch_exits
    if not data[dest_branch] then
        data[dest_branch] = {}
    end

    local level = make_level(branch, depth)
    if not data[dest_branch][level] then
        data[dest_branch][level] = {}
    end

    local current = data[dest_branch][level]
    if current.safe == nil then
        current.safe = true
    end
    if current.los == nil then
        current.los = FEAT_LOS.NONE
    end

    if state.safe == nil then
        state.safe = current.safe
    end
    if state.los == nil then
        state.los = current.los
    end

    local los_changed = current.los < state.los
    if state.safe == current.safe and not los_changed then
        return
    end

    if debug_channel("explore") then
        dsay("Updating " .. dest_branch .. " branch "
            .. (dir == DIR.UP and "exit" or "entrance") .. " stairs " .. " on "
            .. level .. " from " .. stairs_state_string(current) .. " to "
            .. stairs_state_string(state))
    end

    current.safe = state.safe

    if not los_changed then
        return
    end

    current.los = state.los

    if dir == DIR.DOWN then
        -- Update the entry depth in the branch data with the depth where
        -- we found this entry if the entry depth is currently unconfirmed
        -- or if the found depth is higher.
        local parent_br, parent_min, parent_max = parent_branch(dest_branch)
        if branch == parent_br
                and (parent_min ~= parent_max or depth < parent_min) then
            branch_data[dest_branch].parent_min_depth = depth
            branch_data[dest_branch].parent_max_depth = depth
        end
    end

    want_gameplan_update = true
end

function update_escape_hatch(branch, depth, dir, hash, state, force)
    if not state.safe and not state.los then
        error("Undefined stairs state.")
    end

    local data
    if dir == DIR.DOWN then
        data = c_persist.down_hatches
    else
        data = c_persist.up_hatches
    end

    local level = make_level(branch, depth)
    if not data[level] then
        data[level] = {}
    end

    if not data[level][hash] then
        data[level][hash] = {}
    end

    local current = data[level][hash]
    if current.safe == nil then
        current.safe = true
    end
    if current.los == nil then
        current.los = FEAT_LOS.NONE
    end

    if state.safe == nil then
        state.safe = current.safe
    end

    if state.los == nil then
        state.los = current.los
    end

    local los_changed = current.los < state.los
            or force and current.los ~= state.los
    if state.safe ~= current.safe or los_changed then
        if debug_channel("explore") then
            local pos = position_difference(global_pos, unhash_position(hash))
            dsay("Updating escape hatch " .. (dir == DIR.UP and "up" or "down")
                .. " at " .. pos_string(pos) .. " on " .. level
                .. " from " .. stairs_state_string(current) .. " to "
                .. stairs_state_string(state))
        end

        current.safe = state.safe

        if los_changed and not force then
            current.los = state.los
        end
    end
end

function get_escape_hatch_state(branch, depth, map_pos)
    local level = make_level(branch, depth)
    local hash = hash_position(map_pos)

    if c_persist.up_hatches[level] and c_persist.up_hatches[level][hash] then
        return c_persist.up_hatches[level][hash]
    elseif c_persist.down_hatches[level]
            and c_persist.down_hatches[level][hash] then
        return c_persist.down_hatches[level][hash]
    else
        return { safe = true, los = FEAT_LOS.NONE }
    end
end

function update_pan_transit(hash, state, force)
    if not state.safe and not state.los then
        error("Undefined stairs state.")
    end

    if not c_persist.pan_transits[hash] then
        c_persist.pan_transits[hash] = {}
    end

    local current = c_persist.pan_transits[hash]
    if current.safe == nil then
        current.safe = true
    end
    if current.los == nil then
        current.los = FEAT_LOS.NONE
    end

    if state.safe == nil then
        state.safe = current.safe
    end

    if state.los == nil then
        state.los = current.los
    end

    local los_changed = current.los < state.los
            or force and current.los ~= state.los
    if state.safe ~= current.safe or los_changed then
        if debug_channel("explore") then
            local pos = position_difference(global_pos, unhash_position(hash))
            dsay("Updating Pan transit at " .. pos_string(pos) .. " from "
                .. stairs_state_string(current) .. " to "
                .. stairs_state_string(state))
        end

        current.safe = state.safe

        if los_changed and not force then
            current.los = state.los
        end
    end
end

function get_pan_transit_state(map_pos)
    local hash = hash_position(map_pos)

    if c_persist.pan_transits[hash] then
        return c_persist.pan_transits[hash]
    else
        return { safe = true, los = FEAT_LOS.NONE }
    end
end

function update_abyssal_stairs(hash, state, force)
    if not state.safe and not state.los then
        error("Undefined stairs state.")
    end

    if not c_persist.abyssal_stairs[hash] then
        c_persist.abyssal_stairs[hash] = {}
    end

    local current = c_persist.abyssal_stairs[hash]
    if current.safe == nil then
        current.safe = true
    end
    if current.los == nil then
        current.los = FEAT_LOS.NONE
    end

    if state.safe == nil then
        state.safe = current.safe
    end

    if state.los == nil then
        state.los = current.los
    end

    local los_changed = current.los < state.los
            or force and current.los ~= state.los
    if state.safe ~= current.safe or los_changed then
        if debug_channel("explore") then
            local pos = position_difference(global_pos, unhash_position(hash))
            dsay("Updating Abyssal stairs at " .. pos_string(pos) .. " from "
                .. stairs_state_string(current) .. " to "
                .. stairs_state_string(state))
        end

        current.safe = state.safe

        if los_changed and not force then
            current.los = state.los
        end
    end
end

function get_abyssal_stairs_state(map_pos)
    local hash = hash_position(map_pos)

    if c_persist.abyssal_stairs[hash] then
        return c_persist.abyssal_stairs[hash]
    else
        return { safe = true, los = FEAT_LOS.NONE }
    end
end

function distance_map_minimum_enemy_distance(dist_map, pspeed)
    local min_dist
    for _, enemy in ipairs(enemy_list) do
        local gpos = position_sum(global_pos, enemy:pos())
        local dist = dist_map.map[gpos.x][gpos.y]

        if dist then
            local speed_diff = enemy:speed() - pspeed
            if speed_diff > 1 then
                dist = dist / 2
            elseif speed_diff > 0 then
                dist = dist / 1.5
            end

            if enemy:is_ranged() then
                dist = dist - 4
            end

            if not min_dist or dist < min_dist then
                min_dist = dist
            end
        end
    end
    return min_dist
end

function get_branch_stairs_state(branch, depth, stairs_branch, dir)
    local level = make_level(branch, depth)
    if dir == DIR.UP then
        if not c_persist.branch_exits[stairs_branch]
                or not c_persist.branch_exits[stairs_branch][level] then
            return { safe = true, los = FEAT_LOS.NONE }
        end

        return c_persist.branch_exits[stairs_branch][level]
    elseif dir == DIR.DOWN then
        if not c_persist.branch_entries[stairs_branch]
                or not c_persist.branch_entries[stairs_branch][level] then
            return { safe = true, los = FEAT_LOS.NONE }
        end

        return c_persist.branch_entries[stairs_branch][level]
    end
end

function get_destination_stairs_state(branch, depth, feat)
    local state
    local dir, num = stone_stairs_type(feat)
    if dir then
        return get_stone_stairs_state(branch, depth + dir, -dir, num)
    end

    local branch, dir = branch_stairs_type(feat)
    if branch then
        if dir == DIR.UP then
            local parent, min_depth, max_depth = parent_branch(branch)
            if min_depth == max_depth then
                return get_branch_stairs_state(parent, min_depth, branch, -dir)
            end
        else
            return get_branch_stairs_state(branch, 1, -dir)
        end
    end
end

function get_stairs_state(branch, depth, feat)
    local state
    local dir, num = stone_stairs_type(feat)
    if dir then
        return get_stone_stairs_state(branch, depth, dir, num)
    end

    local branch, dir = branch_stairs_type(feat)
    if branch then
        return get_branch_stairs_state(where_branch, where_depth, branch, dir)
    end
end

function find_flee_positions()
    flee_positions = {}

    -- Only retreat to stairs marked as safe.
    local stairs_feats = level_stairs_features(where_branch, where_depth,
        DIR.UP)
    local search_feats = {}
    for _, feat in ipairs(stairs_feats) do
        if get_stairs_state(where_branch, where_depth, feat).safe then
            table.insert(search_feats, feat)
        end
    end

    if have_orb
            and where_depth > 1
            -- It's dangerous to hatch through unexplored areas in Zot as
            -- opposed to simply taking an explored route through stone stairs.
            -- So we only take a hatch up in Zot if the destination level is
            -- fully explored.
            and (not in_branch("Zot")
                or explored_level(where_branch, where_depth - 1)) then
        table.insert(search_feats, "escape_hatch_up")
    elseif in_branch("Pan") then
        table.insert(search_feats, "transit_pandemonium")
    end

    local positions, feats = get_feature_map_positions(search_feats)
    local safe_positions = {}
    for i, feat in ipairs(feats) do
        local state
        if feat == "escape_hatch_up" then
            state = get_escape_hatch_state(where_branch, where_depth,
                positions[i])
        elseif feat == "transit_pandemonium" then
            state = get_pan_transit_state(positions[i])
        end
        if not state or state.safe then
            table.insert(safe_positions, positions[i])
        end
    end

    local pspeed = player_speed()
    for _, pos in ipairs(safe_positions) do
        local dist_map = get_distance_map(pos)
        local pdist = dist_map.map[global_pos.x][global_pos.y]
        local edist = distance_map_minimum_enemy_distance(dist_map, pspeed)
        if pdist and (not edist or pdist < edist) then
            table.insert(flee_positions, pos)
        end
    end
end

function best_flee_destination_at(pos)
    local best_dist, best_pos
    for _, flee_pos in ipairs(flee_positions) do
        local dist_map = get_distance_map(flee_pos)
        local dist = dist_map.map[global_pos.x + pos.x][global_pos.y + pos.y]
        local current_dist = dist_map.map[global_pos.x][global_pos.y]
        if dist and current_dist
                and dist < current_dist
                and (not best_dist or dist < best_dist) then
            best_dist = dist
            best_pos = flee_pos
        end
    end
    return best_pos, best_dist
end

function stairs_improvement(pos)
    if not can_retreat_upstairs then
        return INF_DIST
    end

    if supdist(pos) == 0 then
        if feature_is_upstairs(view.feature_at(0, 0)) then
            return 0
        else
            return INF_DIST
        end
    end

    local dist = select(2, best_flee_destination_at(pos))
    if dist then
        return dist
    end

    return INF_DIST
end
