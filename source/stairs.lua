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

function record_stairs(branch, depth, feat, state, force)
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
        if DEBUG_MODE then
            dsay("Updating " .. level .. " stair " .. feat .. " from "
                .. old_state .. " to " .. state, "explore")
        end
        data[level][num] = state

        if not force then
            want_gameplan_update = true
        end
    end
end

function set_stairs(branch, depth, dir, feat_los, min_feat_los)
    local level = make_level(branch, depth)

    if not min_feat_los then
        min_feat_los = feat_los
    end

    for i = 1, num_required_stairs(branch, depth, dir) do
        if stairs_state(branch, depth, dir, num) >= min_feat_los then
            local feat = "stone_stairs_"
                .. (dir == DIR.DOWN and "down_" or "up_") .. ("i"):rep(i)
            record_stairs(branch, depth, feat, feat_los, true)
        end
    end
end

function level_stair_reset(branch, depth, dir)
    set_stairs(branch, depth, dir, FEAT_LOS.REACHABLE)

    local lev = make_level(branch, depth)
    if lev == where then
        map_mode_searches[waypoint_parity][dir_key(dir)] = nil
    elseif lev == previous_where then
        map_mode_searches[3 - waypoint_parity][dir_key(dir)] = nil
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
            return FEAT_LOS.NONE
        end

        return c_persist.upstairs[level][num]
    elseif dir == DIR.DOWN then
        if not c_persist.downstairs[level]
                or not c_persist.downstairs[level][num] then
            return FEAT_LOS.NONE
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
                or util.contains(hell_branches, branch) then
            return 0
        else
            return 3
        end
    elseif dir == DIR.DOWN then
        if depth == branch_depth(branch)
                    or is_portal_branch(branch)
                    or branch == "Tomb"
                    or branch == "Abyss" then
            return 0
        elseif util.contains(hell_branches, branch) then
            return 1
        else
            return 3
        end
    end
end

function count_stairs(branch, depth, dir, state)
    local num_required = num_required_stairs(branch, depth, dir)
    if num_required == 0 then
        return 0
    end

    local num
    local count = 0
    for i = 1, num_required do
        num = "i"
        num = num:rep(i)
        if stairs_state(branch, depth, dir, num) >= state then
            count = count + 1
        end
    end
    return count
end

function have_all_stairs(branch, depth, dir, state)
    local num_required = num_required_stairs(branch, depth, dir)
    if num_required > 0 then
        local num
        for i = 1, num_required do
            num = "i"
            num = num:rep(i)
            if stairs_state(branch, depth, dir, num) < state then
                return false
            end
        end
    end

    return true
end

function find_good_stairs()
    good_stairs = { }

    if not level_has_upstairs then
        return
    end

    local feats = util.copy_table(upstairs_features)
    local exit = branch_exit(where_branch)
    if feature_is_upstairs(exit) then
        table.insert(feats, exit)
    end
    local stair_positions = get_feature_positions(feats)

    local pspeed = player_speed_num()
    for _, pos in ipairs(stair_positions) do
        local dist_map = get_distance_map(pos)
        local pdist = dist_map.map[waypoint.x][waypoint.y]
        if pdist == nil then
            pdist = 10000
        end

        local minmdist = 1000
        for _, enemy in ipairs(enemy_list) do
            local mdist =
                dist_map.map[waypoint.x + enemy.pos.x][waypoint.y + enemy.pos.y]
            if mdist == nil then
                mdist = 10000
            end

            local speed_diff = enemy:speed() - pspeed
            if speed_diff > 1 then
                mdist = mdist / 2
            elseif speed_diff > 0 then
                mdist = mdist / 1.5
            end
            if enemy:is_ranged() then
                mdist = mdist - 4
            end
            if mdist < minmdist then
                minmdist = mdist
            end
        end
        if pdist < minmdist then
            table.insert(good_stairs, pos)
        end
    end
end

function stair_improvement(pos)
    if not level_has_upstairs then
        return 10000
    end

    if x == 0 and y == 0 then
        if feature_is_upstairs(view.feature_at(0, 0)) then
            return 0
        else
            return 10000
        end
    end

    local min_val = 10000
    for _, stair_pos in ipairs(good_stairs) do
        local dist_map = get_distance_map(stair_pos)
        local val = dist_map.map[waypoint.x + x][waypoint.y + y]
        if val and val < dist_map.map[waypoint.x][waypoint.y]
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
        local val = dist_map.map[waypoint.x + pos.x][waypoint.y + pos.y]
        if val and val < dist_map.map[waypoint.x][waypoint.y]
                and val < min_val then
            min_val = val
            best_stair = hash
        end
    end
    target_stair = best_stair
end
