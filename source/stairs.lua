function clear_level_map(num)
    level_map[num] = {}
    for i = -100, 100 do
        level_map[num][i] = {}
    end
    stair_dists[num] = {}
    map_search[num] = {}
end

function record_stairs(branch, depth, feat, state, force)
    local dir, num
    dir, num = stone_stair_type(feat)
    local data = dir == DIR.DOWN and c_persist.downstairs or c_persist.upstairs

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
        map_search[waypoint_parity][dir_key(dir)] = nil
    elseif lev == previous_where then
        map_search[3 - waypoint_parity][dir_key(dir)] = nil
    end

    if where ~= lev then
        dsay("Resetting autoexplore of " .. lev, "explore")
        c_persist.autoexplore[lev] = AUTOEXP.NEEDED
    end
end

function check_stairs_search(feat)
    local dir, num
    dir, num = stone_stair_type(feat)
    if not dir then
        return
    end

    if stairs_state(where_branch, where_depth, dir, num) < FEAT_LOS.EXPLORED then
        stairs_search = feat
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

function record_map_search(parity, key, start_pos, count, end_pos)
    if not map_search[parity][key] then
        map_search[parity][key] = {}
    end

    if not map_search[parity][key][start_pos] then
        map_search[parity][key][start_pos]  = {}
    end

    map_search[parity][key][start_pos][count] = end_pos
end

function record_branch(x, y)
    local feat = view.feature_at(x, y)
    for br, entry in pairs(branch_data) do
        if entry.entrance == feat then
            if not c_persist.branches[br] then
                c_persist.branches[br] = {}
            end

            local state = los_state(x, y)
            -- We already have a suitable entry recorded.
            if c_persist.branches[br][where]
                    and c_persist.branches[br][where] >= state then
                return
            end

            c_persist.branches[br][where] = state

            -- Update the parent entry depth with that of an entry
            -- found in the parent either if the entry depth is
            -- unconfirmed our the found entry is at a lower depth.
            local cur_br, cur_depth = parse_level_range(where)
            local parent_br, parent_min, parent_max = parent_branch(br)
            if cur_br == parent_br
                    and (parent_min ~= parent_max
                        or cur_depth < parent_min) then
                branch_data[br].parent_min_depth = cur_depth
                branch_data[br].parent_max_depth = cur_depth
            end

            want_gameplan_update = true
            return
        end
    end
end

function update_level_map(num)
    local distqueue = {}
    local staircount = #stair_dists[num]
    for j = 1, staircount do
        distqueue[j] = {}
    end

    local dx, dy = travel.waypoint_delta(num)
    local mapqueue = {}
    for x = -los_radius, los_radius do
        for y = -los_radius, los_radius do
            local feat = view.feature_at(x, y)
            if feat:find("stone_stairs") then
                record_stairs(where_branch, where_depth, feat, los_state(x, y))
            elseif feat:find("enter_") then
                record_branch(x, y)
            elseif feat:find("altar_") and feat ~= "altar_ecumenical" then
                record_altar(x, y)
            end
            table.insert(mapqueue, {x + dx, y + dy})
        end
    end

    local newcount = staircount
    local first = 1
    local last = #mapqueue
    local x, y, feat, val, oldval
    while first < last do
        if first % 1000 == 0 then
            coroutine.yield()
        end
        x = mapqueue[first][1]
        y = mapqueue[first][2]
        first = first + 1
        feat = view.feature_at(x - dx, y - dy)
        if feat ~= "unseen" then
            if level_map[num][x][y] == nil then
                for ddx = -1, 1 do
                    for ddy = -1, 1 do
                        if ddx ~= 0 or ddy ~= 0 then
                            last = last + 1
                            mapqueue[last] = {x + ddx, y + ddy}
                        end
                    end
                end
            end
            if travel.feature_traversable(feat)
                    and not travel.feature_solid(feat) then
                if level_map[num][x][y] ~= "." then
                    if feat_is_upstairs(feat) then
                        newcount = #stair_dists[num] + 1
                        stair_dists[num][newcount] = {}
                        for i = -100, 100 do
                            stair_dists[num][newcount][i] = {}
                        end
                        stair_dists[num][newcount][x][y] = 0
                        distqueue[newcount] = {{x, y}}
                    end
                    for j = 1, staircount do
                        oldval = stair_dists[num][j][x][y]
                        for ddx = -1, 1 do
                            for ddy = -1, 1 do
                                if (ddx ~= 0 or ddy ~= 0) then
                                    val = stair_dists[num][j][x + ddx][y + ddy]
                                    if val ~= nil
                                            and (oldval == nil
                                                or oldval > val + 1) then
                                        oldval = val + 1
                                    end
                                end
                            end
                        end
                        if stair_dists[num][j][x][y] ~= oldval then
                            stair_dists[num][j][x][y] = oldval
                            table.insert(distqueue[j], {x, y})
                        end
                    end
                end
                level_map[num][x][y] = "."
            else
                level_map[num][x][y] = "#"
            end
        end
    end

    for j = 1, newcount do
        update_dist_map(stair_dists[num][j], distqueue[j])
    end

    if map_search_key then
        local feat = view.feature_at(0, 0)
        -- We assume we've landed on the next feature in our current "X<key>"
        -- cycle because the feature at our position uses that key.
        if feat_uses_map_key(map_search_key, feat) then
            record_map_search(num, map_search_key, map_search_pos,
                map_search_count, 100 * dx + dy)
            check_stairs_search(feat)
        end
        map_search_key = nil
        map_search_pos = nil
        map_search_count = nil
    end
end

function update_dist_map(dist_map, queue)
    local first = 1
    local last = #queue
    local x, y, val
    while first <= last do
        if first % 300 == 0 then
            coroutine.yield()
        end
        x = queue[first][1]
        y = queue[first][2]
        first = first + 1
        val = dist_map[x][y] + 1
        for dx = -1, 1 do
            for dy = -1, 1 do
                if (dx ~= 0 or dy ~= 0)
                        and level_map[waypoint_parity][x + dx][y + dy]
                            == "." then
                    oldval = dist_map[x + dx][y + dy]
                    if oldval == nil or oldval > val then
                        dist_map[x + dx][y + dy] = val
                        last = last + 1
                        queue[last] = {x + dx, y + dy}
                    end
                end
            end
        end
    end
end

function find_good_stairs()
    good_stair_list = { }

    if not can_waypoint then
        return
    end

    local num = waypoint_parity
    local dx, dy = travel.waypoint_delta(num)
    local staircount = #(stair_dists[num])
    local pdist, mdist, minmdist, speed_diff
    local pspeed = player_speed_num()
    for i = 1, staircount do
        pdist = stair_dists[num][i][dx][dy]
        if pdist == nil then
            pdist = 10000
        end
        minmdist = 1000
        for _, e in ipairs(enemy_list) do
            mdist = stair_dists[num][i][dx + e.x][dy + e.y]
            if mdist == nil then
                mdist = 10000
            end
            speed_diff = mon_speed_num(e.m) - pspeed
            if speed_diff > 1 then
                mdist = mdist / 2
            elseif speed_diff > 0 then
                mdist = mdist / 1.5
            end
            if is_ranged(e.m) then
                mdist = mdist - 4
            end
            if mdist < minmdist then
                minmdist = mdist
            end
        end
        if pdist < minmdist then
            table.insert(good_stair_list, i)
        end
    end
end

function stair_improvement(x, y)
    if not can_waypoint then
        return 10000
    end
    if x == 0 and y == 0 then
        if feat_is_upstairs(view.feature_at(0, 0)) then
            return 0
        else
            return 10000
        end
    end
    local num = waypoint_parity
    local dx, dy = travel.waypoint_delta(num)
    local val
    local minval = 10000
    for _, i in ipairs(good_stair_list) do
        val = stair_dists[num][i][dx + x][dy + y]
        if val < stair_dists[num][i][dx][dy] and val < minval then
            minval = val
        end
    end
    return minval
end

function set_stair_target(c)
    local x, y = vi_to_delta(c)
    local num = waypoint_parity
    local dx, dy = travel.waypoint_delta(num)
    local val
    local minval = 10000
    local best_stair
    for _, i in ipairs(good_stair_list) do
        val = stair_dists[num][i][dx + x][dy + y]
        if val < stair_dists[num][i][dx][dy] and val < minval then
            minval = val
            best_stair = i
        end
    end
    target_stair = best_stair
end

function los_state(x, y)
    if you.see_cell_solid_see(x, y) then
        return FEAT_LOS.REACHABLE
    elseif you.see_cell_no_trans(x, y) then
        return FEAT_LOS.DIGGABLE
    end
    return FEAT_LOS.SEEN
end
