------------------
-- Stair-related functions

-- Stair direction enum
DIR = { UP = -1, DOWN = 1 }

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

function level_stairs_features(branch, depth, dir)
    local feats
    if dir == DIR.UP then
        if is_portal_branch(branch)
                or branch == "Abyss"
                or branch == "Pan"
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

function record_stairs(branch, depth, feat, state, force)
    if not state.safe and not state.los then
        error("Undefined stairs state.")
    end

    local dir, num
    dir, num = stone_stair_type(feat)

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

    if data[level][num].safe == nil then
        data[level][num].safe = true
    end
    if data[level][num].los == nil then
        data[level][num].los = FEAT_LOS.NONE
    end

    if state.safe == nil then
        state.safe = data[level][num].safe
    end

    if state.los == nil then
        state.los = data[level][num].los
    end

    local los_changed = data[level][num].los < state.los
            or force and data[level][num].los ~= state.los
    if state.safe ~= data[level][num].safe or los_changed then
        if debug_channel("explore") then
            dsay("Updating " .. level .. " stairs " .. feat .. " from "
                .. stairs_state_string(data[level][num]) .. " to "
                .. stairs_state_string(state))
        end

        data[level][num].safe = state.safe

        if los_changed and not force then
            data[level][num].los = state.los
            want_gameplan_update = true
        end

    end
end

function set_stairs(branch, depth, dir, state, min_los)
    local level = make_level(branch, depth)

    if not min_los then
        min_los = state.los
    end

    for i = 1, num_required_stairs(branch, depth, dir) do
        if stairs_state(branch, depth, dir, num).los >= min_los then
            local feat = "stone_stairs_"
                .. (dir == DIR.DOWN and "down_" or "up_") .. ("i"):rep(i)
            record_stairs(branch, depth, feat, state, true)
        end
    end
end

function stairs_reset(branch, depth, dir)
    set_stairs(branch, depth, dir, { los = FEAT_LOS.REACHABLE })

    local lev = make_level(branch, depth)
    if lev == where then
        map_mode_searches[dir_key(dir)] = nil
    elseif lev == previous_where then
        level_map_mode_searches[3 - level_parity][dir_key(dir)] = nil
    end

    if where ~= lev then
        dsay("Resetting autoexplore of " .. lev, "explore")
        c_persist.autoexplore[lev] = AUTOEXP.NEEDED
    end
end

function stairs_state(branch, depth, dir, num)
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

function destination_stairs_state(branch, depth, dir, num)
    return stairs_state(branch, depth + dir, -dir, num)
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
        if stairs_state(branch, depth, dir, num).los >= los then
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
            if stairs_state(branch, depth, dir, num).los < los then
                return false
            end
        end
    end

    return true
end

function minimum_enemy_stair_distance(dist_map, pspeed)
    local min_dist = 1000
    for _, enemy in ipairs(enemy_list) do
        local gpos = position_sum(global_pos, enemy:pos())
        local dist = dist_map.map[gpos.x][gpos.y]
        if dist == nil then
            dist = 10000
        end

        local speed_diff = enemy:speed() - pspeed
        if speed_diff > 1 then
            dist = dist / 2
        elseif speed_diff > 0 then
            dist = dist / 1.5
        end

        if enemy:is_ranged() then
            dist = dist - 4
        end

        if dist < min_dist then
            min_dist = dist
        end
    end
    return min_dist
end

function find_good_stairs()
    good_stairs = {}

    if not can_retreat_upstairs then
        return
    end

    local feats = util.copy_table(upstairs_features)
    local exit = branch_exit(where_branch)
    if feature_is_upstairs(exit) then
        table.insert(feats, exit)
    end
    local stair_positions = get_feature_positions(feats)

    local pspeed = player_speed()
    for _, pos in ipairs(stair_positions) do
        local dist_map = get_distance_map(pos)
        local pdist = dist_map.map[global_pos.x][global_pos.y]
        if pdist == nil then
            pdist = 10000
        end

        if pdist < minimum_enemy_stair_distance(dist_map, pspeed) then
            table.insert(good_stairs, pos)
        end
    end
end

function stair_improvement(pos)
    if not can_retreat_upstairs then
        return 10000
    end

    if supdist(pos) == 0 then
        if feature_is_upstairs(view.feature_at(0, 0)) then
            return 0
        else
            return 10000
        end
    end

    local min_val = 10000
    for _, stair_pos in ipairs(good_stairs) do
        local dist_map = get_distance_map(stair_pos)
        local val = dist_map.map[global_pos.x + pos.x][global_pos.y + pos.y]
        if val and val < dist_map.map[global_pos.x][global_pos.y]
                and val < min_val then
            min_val = val
        end
    end
    return min_val
end

function set_stair_target(c)
    local pos = vi_to_delta(c)
    local min_val = 10000
    local best_stair
    for _, stair_pos in ipairs(good_stairs) do
        local dist_map = get_distance_map(stair_pos)
        local val = dist_map.map[global_pos.x + pos.x][global_pos.y + pos.y]
        if val and val < dist_map.map[global_pos.x][global_pos.y]
                and val < min_val then
            min_val = val
            best_stair = hash
        end
    end
    target_stair = best_stair
end

function mark_stairs_unsafe(branch, depth, feat)
    local dir, num
    dir, num = stone_stair_type(feat)

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

    local old_state = not data[level][num] and FEAT_LOS.NONE
        or data[level][num]
    if old_state < state or force then
        if debug_channel("explore") then
            dsay("Updating " .. level .. " stair " .. feat .. " from "
                .. old_state .. " to " .. state)
        end
        data[level][num] = state

        if not force then
            want_gameplan_update = true
        end
    end
end
