------------------
-- Stair-related functions

-- Stair direction enum
const.dir = { up = -1, down = 1 }

const.inf_dist = 10000

const.upstairs = {
    "stone_stairs_up_i",
    "stone_stairs_up_ii",
    "stone_stairs_up_iii",
}

const.downstairs = {
    "stone_stairs_down_i",
    "stone_stairs_down_ii",
    "stone_stairs_down_iii",
}

const.escape_hatches = {
    [const.dir.up] = "escape_hatch_up",
    [const.dir.down] = "escape_hatch_down",
}

function dir_key(dir)
    return dir == const.dir.down and ">"
        or (dir == const.dir.up and "<" or nil)
end

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
    if dir == const.dir.up then
        if is_portal_branch(branch)
                or branch == "Abyss"
                or is_hell_branch(branch)
                or depth == 1 then
            feats = { branch_exit(branch) }
        else
            feats = util.copy_table(const.upstairs)
        end

        if want_to_use_escape_hatches(const.dir.up) then
            table.insert(feats, "escape_hatch_up")
        end
    elseif dir == const.dir.down then
        if branch == "Abyss" and depth < branch_depth("Abyss") then
            feats = { "abyssal_stair" }
        elseif branch == "Pan" then
            feats = { "transit_pandemonium" }
        elseif is_hell_branch(branch) and depth < branch_depth(branch) then
            feats = { const.downstairs[1] }
        elseif depth < branch_depth(branch) then
            feats = util.copy_table(const.downstairs)
        end
    end
    return feats
end

function stairs_state_string(state)
    return enum_string(state.feat, const.feat_state) .. "/"
        .. (state.safe and "safe" or "unsafe")
end

function update_stone_stairs(branch, depth, dir, num, state, force)
    if state.safe == nil and not state.feat then
        error("Undefined stone stairs state.")
    end

    local data
    if dir == const.dir.down then
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
    if current.feat == nil then
        current.feat = const.explore.none
    end

    if state.safe == nil then
        state.safe = current.safe
    end

    if state.feat == nil then
        state.feat = current.feat
    end

    local feat_state_changed = current.feat < state.feat
            or force and current.feat ~= state.feat
    if state.safe ~= current.safe or feat_state_changed then
        if debug_channel("explore") then
            dsay("Updating stone " .. (dir == const.dir.up and "up" or "down")
                .. "stairs " .. num .. " on " .. level
                .. " from " .. stairs_state_string(current) .. " to "
                .. stairs_state_string(state))
        end

        current.safe = state.safe

        if feat_state_changed then
            current.feat = state.feat
            want_goal_update = true
        end
    end
end

function update_all_stone_stairs(branch, depth, dir, state, max_feat_state)
    for i = 1, num_required_stairs(branch, depth, dir) do
        local num = ("i"):rep(i)
        local cur_state = get_stone_stairs(branch, depth, dir, num)
        if cur_state and (not max_feat_state
                or cur_state.feat >= state.feat) then
            update_stone_stairs(branch, depth, dir, num, state, true)
        end
    end
end

function reset_stone_stairs(branch, depth, dir)
    update_all_stone_stairs(branch, depth, dir,
        { feat = const.explore.reachable }, true)

    local level = make_level(branch, depth)
    if level == where then
        map_mode_searches[dir_key(dir)] = nil
    elseif level == previous_where then
        map_mode_searches_cache[3 - cache_parity][dir_key(dir)] = nil
    end

    if where ~= level then
        reset_autoexplore(level)
    end
end

function get_stone_stairs(branch, depth, dir, num)
    local level = make_level(branch, depth)
    if dir == const.dir.up then
        if not c_persist.upstairs[level]
                or not c_persist.upstairs[level][num] then
            return
        end

        return c_persist.upstairs[level][num]
    elseif dir == const.dir.down then
        if not c_persist.downstairs[level]
                or not c_persist.downstairs[level][num] then
            return
        end

        return c_persist.downstairs[level][num]
    end
end

function num_required_stairs(branch, depth, dir)
    if dir == const.dir.up then
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
    elseif dir == const.dir.down then
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

function count_stairs(branch, depth, dir, feat_state)
    local num_required = num_required_stairs(branch, depth, dir)
    if num_required == 0 then
        return 0
    end

    local count = 0
    for i = 1, num_required do
        local num = ("i"):rep(i)
        local state = get_stone_stairs(branch, depth, dir, num)
        if state and state.feat >= feat_state then
            count = count + 1
        end
    end
    return count
end

function have_all_stairs(branch, depth, dir, feat_state)
    local num_required = num_required_stairs(branch, depth, dir)
    if num_required > 0 then
        for i = 1, num_required do
            local num = ("i"):rep(i)
            local state = get_stone_stairs(branch, depth, dir, num)
            if not state or state.feat < feat_state then
                return false
            end
        end
    end

    return true
end

function update_branch_stairs(branch, depth, dest_branch, dir, state, force)
    if state.safe == nil and not state.feat then
        error("Undefined branch stairs state.")
    end

    local data = dir == const.dir.down and c_persist.branch_entries
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
    if current.feat == nil then
        current.feat = const.explore.none
    end

    if state.safe == nil then
        state.safe = current.safe
    end
    if state.feat == nil then
        state.feat = current.feat
    end

    local feat_state_changed = current.feat < state.feat
        or force and current.feat ~= state.feat
    if state.safe == current.safe and not feat_state_changed then
        return
    end

    if debug_channel("explore") then
        dsay("Updating " .. dest_branch .. " branch "
            .. (dir == const.dir.up and "exit" or "entrance") .. " stairs "
            .. " on " .. level .. " from " .. stairs_state_string(current)
            .. " to " .. stairs_state_string(state))
    end

    current.safe = state.safe

    if not feat_state_changed then
        return
    end

    current.feat = state.feat

    if dir == const.dir.down then
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

    want_goal_update = true
end

function update_escape_hatch(branch, depth, dir, hash, state, force)
    if state.safe == nil and not state.feat then
        error("Undefined escape hatch state.")
    end

    local data
    if dir == const.dir.down then
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
    if current.feat == nil then
        current.feat = const.explore.none
    end

    if state.safe == nil then
        state.safe = current.safe
    end

    if state.feat == nil then
        state.feat = current.feat
    end

    local feat_state_changed = current.feat < state.feat
            or force and current.feat ~= state.feat
    if state.safe ~= current.safe or feat_state_changed then
        if debug_channel("explore") then
            dsay("Updating escape hatch " .. " on " .. level .. " at "
                .. cell_string_from_map_position(unhash_position(hash))
                .. " from " .. stairs_state_string(current) .. " to "
                .. stairs_state_string(state))
        end

        current.safe = state.safe

        if feat_state_changed then
            current.feat = state.feat
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
    if state.safe == nil and not state.feat then
        error("Undefined Pan transit state.")
    end

    if not c_persist.pan_transits[hash] then
        c_persist.pan_transits[hash] = {}
    end

    local current = c_persist.pan_transits[hash]
    if current.safe == nil then
        current.safe = true
    end
    if current.feat == nil then
        current.feat = const.explore.none
    end

    if state.safe == nil then
        state.safe = current.safe
    end

    if state.feat == nil then
        state.feat = current.feat
    end

    local feat_state_changed = current.feat < state.feat
            or force and current.feat ~= state.feat
    if state.safe ~= current.safe or feat_state_changed then
        if debug_channel("explore") then
            dsay("Updating Pan transit at "
                .. los_pos_string(unhash_position(hash)) .. " from "
                .. stairs_state_string(current) .. " to "
                .. stairs_state_string(state))
        end

        current.safe = state.safe

        if feat_state_changed then
            current.feat = state.feat
        end
    end
end

function get_map_pan_transit(pos)
    return c_persist.pan_transits[hash_position(pos)]
end

function update_abyssal_stairs(hash, state, force)
    if state.safe == nil and not state.feat then
        error("Undefined Abyssal stairs state.")
    end

    if not c_persist.abyssal_stairs[hash] then
        c_persist.abyssal_stairs[hash] = {}
    end

    local current = c_persist.abyssal_stairs[hash]
    if current.safe == nil then
        current.safe = true
    end
    if current.feat == nil then
        current.feat = const.explore.none
    end

    if state.safe == nil then
        state.safe = current.safe
    end

    if state.feat == nil then
        state.feat = current.feat
    end

    local feat_state_changed = current.feat < state.feat
            or force and current.feat ~= state.feat
    if state.safe ~= current.safe or feat_state_changed then
        if debug_channel("explore") then
            dsay("Updating Abyssal stairs at "
                .. los_pos_string(unhash_position(hash)) .. " from "
                .. stairs_state_string(current) .. " to "
                .. stairs_state_string(state))
        end

        current.safe = state.safe

        if feat_state_changed then
            current.feat = state.feat
        end
    end
end

function get_map_abyssal_stairs(pos)
    return c_persist.abyssal_stairs[hash_position(pos)]
end

function get_branch_stairs(branch, depth, stairs_branch, dir)
    local level = make_level(branch, depth)
    if dir == const.dir.up then
        if not c_persist.branch_exits[stairs_branch]
                or not c_persist.branch_exits[stairs_branch][level] then
            return
        end

        return c_persist.branch_exits[stairs_branch][level]
    elseif dir == const.dir.down then
        if not c_persist.branch_entries[stairs_branch]
                or not c_persist.branch_entries[stairs_branch][level] then
            return
        end

        return c_persist.branch_entries[stairs_branch][level]
    end
end

function get_destination_stairs(branch, depth, feat)
    local dir, num = stone_stairs_type(feat)
    if dir then
        return get_stone_stairs(branch, depth + dir, -dir, num)
    end

    local branch, dir = branch_stairs_type(feat)
    if branch then
        if dir == const.dir.up then
            local parent, min_depth, max_depth = parent_branch(branch)
            if parent and min_depth == max_depth then
                return get_branch_stairs(parent, min_depth, branch, -dir)
            end
        else
            return get_branch_stairs(branch, 1, branch, -dir)
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
