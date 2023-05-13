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
Return a list of stair features we're allowed to take on the given level and in
the given direction that takes us to the next depth for that direction. For
going up, this includes branch exits that take us out of the branch. Up escape
hatches are included on the Orb run under the right conditions. For going down,
this does not include any branch entrances, but does include features in Abyss
and Pan that lead to the next level in the branch.
--]]
function level_stairs_features(branch, depth, dir)
    local feats
    if dir == DIR.UP then
        if is_portal_branch(branch)
                or branch == "Abyss"
                or is_hell_branch(branch)
                or depth == 1 then
            feats = { branch_exit(branch) }
        else
            feats = util.copy_table(upstairs_features)
        end

        if want_to_use_escape_hatches(DIR.UP) then
            table.insert(feats, "escape_hatch_up")
        end
    elseif dir == DIR.DOWN then
        if branch == "Abyss" then
            feats = { "abyssal_stair" }
        elseif branch == "Pan" then
            feats = { "transit_pandemonium" }
        elseif is_hell_branch(branch) and depth < branch_depth(branch) then
            feats = { downstairs_features[1] }
        elseif depth < branch_depth(branch) then
            feats = util.copy_table(downstairs_features)
        end
    end
    return feats
end

function stairs_state_string(state)
    return enum_string(state.los, FEAT_LOS) .. "/"
        .. (state.safe and "safe" or "unsafe")
end

function update_stone_stairs(branch, depth, dir, num, state, force)
    if state.safe == nil and not state.los then
        error("Undefined stone stairs state.")
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
        local cur_state = get_stone_stairs(branch, depth, dir, i)
        if cur_state and (not max_los or cur_state.los >= state.los) then
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

function get_stone_stairs(branch, depth, dir, num)
    local level = make_level(branch, depth)
    if dir == DIR.UP then
        if not c_persist.upstairs[level]
                or not c_persist.upstairs[level][num] then
            return
        end

        return c_persist.upstairs[level][num]
    elseif dir == DIR.DOWN then
        if not c_persist.downstairs[level]
                or not c_persist.downstairs[level][num] then
            return
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
                or is_hell_branch(branch) then
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
        elseif is_hell_branch(branch) then
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
        local state = get_stone_stairs(branch, depth, dir, num)
        if state and state.los >= los then
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
            local state = get_stone_stairs(branch, depth, dir, num)
            if not state or state.los < los then
                return false
            end
        end
    end

    return true
end

function update_branch_stairs(branch, depth, dest_branch, dir, state)
    if state.safe == nil and not state.los then
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
    if state.safe == nil and not state.los then
        error("Undefined escape hatch state.")
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
            local pos = position_difference(unhash_position(hash), global_pos)
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

function get_map_escape_hatch(branch, depth, pos)
    local level = make_level(branch, depth)
    local hash = hash_position(pos)
    if c_persist.up_hatches[level] and c_persist.up_hatches[level][hash] then
        return c_persist.up_hatches[level][hash]
    elseif c_persist.down_hatches[level]
            and c_persist.down_hatches[level][hash] then
        return c_persist.down_hatches[level][hash]
    end
end

function update_pan_transit(hash, state, force)
    if state.safe == nil and not state.los then
        error("Undefined Pan transit state.")
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
            local pos = position_difference(unhash_position(hash), global_pos)
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

function get_map_pan_transit(pos)
    return c_persist.pan_transits[hash_position(pos)]
end

function update_abyssal_stairs(hash, state, force)
    if state.safe == nil and not state.los then
        error("Undefined Abyssal stairs state.")
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
            local pos = position_difference(unhash_position(hash), global_pos)
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

function get_map_abyssal_stairs(pos)
    return c_persist.abyssal_stairs[hash_position(pos)]
end

function get_branch_stairs(branch, depth, stairs_branch, dir)
    local level = make_level(branch, depth)
    if dir == DIR.UP then
        if not c_persist.branch_exits[stairs_branch]
                or not c_persist.branch_exits[stairs_branch][level] then
            return
        end

        return c_persist.branch_exits[stairs_branch][level]
    elseif dir == DIR.DOWN then
        if not c_persist.branch_entries[stairs_branch]
                or not c_persist.branch_entries[stairs_branch][level] then
            return
        end

        return c_persist.branch_entries[stairs_branch][level]
    end
end

function get_destination_stairs(branch, depth, feat)
    local state
    local dir, num = stone_stairs_type(feat)
    if dir then
        return get_stone_stairs(branch, depth + dir, -dir, num)
    end

    local branch, dir = branch_stairs_type(feat)
    if branch then
        if dir == DIR.UP then
            local parent, min_depth, max_depth = parent_branch(branch)
            if min_depth == max_depth then
                return get_branch_stairs(parent, min_depth, branch, -dir)
            end
        else
            return get_branch_stairs(branch, 1, -dir)
        end
    end
end

function get_stairs(branch, depth, feat)
    local dir, num = stone_stairs_type(feat)
    if dir then
        return get_stone_stairs(branch, depth, dir, num)
    end

    local branch, dir = branch_stairs_type(feat)
    if branch then
        return get_branch_stairs(where_branch, where_depth, branch, dir)
    end
end
