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

        if want_to_use_escape_hatch(const.dir.up) then
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
    return string.format("%s/%s/threat:%s",
        enum_string(state.explore, const.explore),
        (state.safe and "safe" or "unsafe"),
        state.threat)
end

function update_stone_stairs_state(branch, depth, dir, num, state, force)
    if state.safe == nil and not state.explore and not state.threat then
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

    local current = data[level][num]
    if not current then
        current = {}
        cleanup_feature_state(current)
        data[level][num] = current
    end

    if state.safe == nil then
        state.safe = current.safe
    end
    if state.explore == nil then
        state.explore = current.explore
    end
    if state.threat == nil then
        state.threat = current.threat
    end

    local explore_state_changed = current.explore < state.explore
        or force and current.explore ~= state.explore
    if state.safe == current.safe
            and not explore_state_changed
            and state.threat == current.threat then
        return
    end

    if debug_channel("map") then
        dsayf("Updating stone %s stairs %s on %s from %s to %s",
            enum_string(dir, const.dir),
            num,
            level,
            stairs_state_string(current),
            stairs_state_string(state))
    end

    current.safe = state.safe
    current.threat = state.threat
    if explore_state_changed then
        current.explore = state.explore
        qw.want_goal_update = true
    end
end

function update_all_stone_stairs_states(branch, depth, dir, state,
        max_explore_state)
    for i = 1, num_required_stairs(branch, depth, dir) do
        local num = ("i"):rep(i)
        local cur_state = get_stone_stairs_state(branch, depth, dir, num)
        if cur_state
                and (not max_explore_state
                    or cur_state.explore >= state.explore) then
            update_stone_stairs_state(branch, depth, dir, num, state, true)
        end
    end
end

function reset_stone_stairs_state(branch, depth, dir)
    update_all_stone_stairs_states(branch, depth, dir,
        { explore = const.explore.reachable }, true)

    if where ~= make_level(branch, depth) then
        reset_autoexplore(branch, depth)
    end
end

function get_stone_stairs_state(branch, depth, dir, num)
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

function count_stairs(branch, depth, dir, explore_state)
    local num_required = num_required_stairs(branch, depth, dir)
    if num_required == 0 then
        return 0
    end

    local count = 0
    for i = 1, num_required do
        local num = ("i"):rep(i)
        local state = get_stone_stairs_state(branch, depth, dir, num)
        if state and state.explore >= explore_state then
            count = count + 1
        end
    end
    return count
end

function have_all_stairs(branch, depth, dir, explore_state)
    local num_required = num_required_stairs(branch, depth, dir)
    if num_required > 0 then
        for i = 1, num_required do
            local num = ("i"):rep(i)
            local state = get_stone_stairs_state(branch, depth, dir, num)
            if not state or state.explore < explore_state then
                return false
            end
        end
    end

    return true
end

function update_branch_stairs_state(branch, depth, dest_branch, dir, state,
        force)
    if state.safe == nil and not state.explore and not state.threat then
        error("Undefined branch stairs state.")
    end

    local data = dir == const.dir.down and c_persist.branch_entries
        or c_persist.branch_exits
    if not data[dest_branch] then
        data[dest_branch] = {}
    end

    local level = make_level(branch, depth)
    local current = data[dest_branch][level]
    if not current then
        current = {}
        cleanup_feature_state(current)
        data[dest_branch][level] = current
    end

    if state.safe == nil then
        state.safe = current.safe
    end
    if state.explore == nil then
        state.explore = current.explore
    end
    if state.threat == nil then
        state.threat = current.threat
    end

    local explore_state_changed = current.explore < state.explore
        or force and current.explore ~= state.explore
    if state.safe == current.safe
            and not explore_state_changed
            and state.threat == current.threat then
        return
    end

    if debug_channel("map") then
        dsayf("Updating %s branch %s stairs on %s from %s to %s",
            dest_branch,
            (dir == const.dir.up and "exit" or "entrance"),
            level,
            stairs_state_string(current),
            stairs_state_string(state))
    end

    current.safe = state.safe
    current.threat = state.threat

    if not explore_state_changed then
        return
    end

    current.explore = state.explore
    qw.want_goal_update = true

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
end

function get_escape_hatch_state(branch, depth, map_pos)
    local level = make_level(branch, depth)
    if c_persist.up_hatches[level]
            and c_persist.up_hatches[level][map_pos.hash] then
        return c_persist.up_hatches[level][map_pos.hash]
    elseif c_persist.down_hatches[level]
            and c_persist.down_hatches[level][map_pos.hash] then
        return c_persist.down_hatches[level][map_pos.hash]
    end
end

function update_escape_hatch_state(branch, depth, dir, map_pos, state, force)
    if state.safe == nil and not state.explore and not state.threat then
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

    local current = data[level][map_pos.hash]
    if not current then
        current = {}
        cleanup_feature_state(current)
        data[level][map_pos.hash] = current
    end

    if state.safe == nil then
        state.safe = current.safe
    end
    if state.explore == nil then
        state.explore = current.explore
    end
    if state.threat == nil then
        state.threat = current.threat
    end

    local explore_state_changed = current.explore < state.explore
            or force and current.explore ~= state.explore
    if state.safe == current.safe
            and not explore_state_changed
            and state.threat == current.threat then
        return
    end

    if debug_channel("map") then
        dsayf("Updating escape hatch on %s at %s from %s to %s",
            level,
            cell_string_from_map_position(map_pos),
            stairs_state_string(current),
            stairs_state_string(state))
    end

    current.safe = state.safe
    current.threat = state.threat
    if explore_state_changed then
        current.explore = state.explore
    end
end

function update_pan_transit_state(map_pos, state, force)
    if state.safe == nil and not state.explore and not state.threat then
        error("Undefined Pan transit state.")
    end

    local current = c_persist.pan_transits[map_pos.hash]
    if not current then
        current = {}
        cleanup_feature_state(current)
        c_persist.pan_transits[map_pos.hash] = current
    end

    if state.safe == nil then
        state.safe = current.safe
    end
    if state.explore == nil then
        state.explore = current.explore
    end
    if state.threat == nil then
        state.threat = current.threat
    end

    local explore_state_changed = current.explore < state.explore
            or force and current.explore ~= state.explore
    if state.safe == current.safe
            and not explore_state_changed
            and state.threat == current.threat then
        return
    end

    if debug_channel("map") then
        dsayf("Updating Pan transit at %s from %s to %s",
            cell_string_from_map_position(map_pos),
            stairs_state_string(current),
            stairs_state_string(state))
    end

    current.safe = state.safe
    current.threat = state.threat
    if explore_state_changed then
        current.explore = state.explore
    end
end

function update_abyssal_stairs_state(map_pos, state, force)
    if state.safe == nil and not state.explore and not state.threat then
        error("Undefined Abyssal stairs state.")
    end

    local current = c_persist.abyssal_stairs[map_pos.hash]
    if not current then
        current = {}
        cleanup_feature_state(current)
        c_persist.abyssal_stairs[map_pos.hash] = current
    end

    if state.safe == nil then
        state.safe = current.safe
    end
    if state.explore == nil then
        state.explore = current.explore
    end
    if state.threat == nil then
        state.threat = current.threat
    end

    local explore_state_changed = current.explore < state.explore
            or force and current.explore ~= state.explore
    if state.safe == current.safe
            and not explore_state_changed
            and state.threat == current.threat then
        return
    end

    if debug_channel("map") then
        dsayf("Updating Abyssal stairs at %s from %s to %s",
            cell_string_from_map_position(map_pos),
            stairs_state_string(current),
            stairs_state_string(state))
    end

    current.safe = state.safe
    current.threat = state.threat
    if explore_state_changed then
        current.explore = state.explore
    end
end

function get_branch_stairs_state(branch, depth, stairs_branch, dir)
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

function get_destination_stairs_state(branch, depth, feat)
    local dir, num = stone_stairs_type(feat)
    if dir then
        return get_stone_stairs_state(branch, depth + dir, -dir, num)
    end

    local branch, dir = branch_stairs_type(feat)
    if branch then
        if dir == const.dir.up then
            local parent, min_depth, max_depth = parent_branch(branch)
            if parent and min_depth == max_depth then
                return get_branch_stairs_state(parent, min_depth, branch, -dir)
            end
        else
            return get_branch_stairs_state(branch, 1, branch, -dir)
        end
    end
end

function get_stairs_state(branch, depth, feat)
    local dir, num = stone_stairs_type(feat)
    if dir then
        return get_stone_stairs_state(branch, depth, dir, num)
    end

    local branch, dir = branch_stairs_type(feat)
    if branch then
        return get_branch_stairs_state(where_branch, where_depth, branch, dir)
    end
end

function want_to_use_escape_hatch(dir)
    return dir == const.dir.up
        and goal_status == "Escape"
        and not branch_is_temporary(where_branch)
        and not in_branch("Tomb")
        and where_depth > 1
        -- It's dangerous to hatch through unexplored areas in Zot as opposed
        -- to simply taking an explored route through stone stairs. So we only
        -- take a hatch up in Zot if the destination level is fully explored.
        and (where_branch ~= "Zot"
            or explored_level(where_branch, where_depth - 1))
end

function want_to_take_upstairs()
    if not qw.can_flee_upstairs
            -- Assume we'd rather follow through with our teleport rather than
            -- take stairs.
            or you.teleporting()
            or you.caught()
            or you.constricted()
            or goal_status ~= "Escape"
                and (check_brothers_in_arms(3)
                    or check_divine_warriors(3)) then
        return false
    end

    local feat = feature_at(const.origin)
    if feature_is_upstairs(feat) then
        local state = get_destination_stairs_state(where_branch, where_depth,
            feat)
        if state and not state.safe then
            return false
        end
    elseif escape_hatch_type(feat) ~= const.dir.up
            or not want_to_use_escape_hatch(const.dir.up) then
        return false
    end

    local n = stairdance_count[where] or 0
    if n >= 20 then
        return false
    end

    local only_when_safe = you.berserk() or hp_is_low(33)
    local follow_count = count_stairs_followers(1)
    local other_count = #qw.enemy_list - follow_count
    if only_when_safe and follow_count > 0 then
        return false
    end

    -- We have no stair followers, so we only go up if we're fleeing for some
    -- reason.
    if follow_count == 0 and want_to_flee()
            -- We have stair followers, but there are even more non-following
            -- monsters around, so we go up to fight the following monsters in
            -- probable safety.
            or other_count > 0 and follow_count > 0 then
        stairdance_count[where] = n + 1
        return true
    end

    return false
end
