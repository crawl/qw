----------------------
-- Stair-related plans

function go_upstairs(confirm)
    magic("<" .. (confirm and "Y" or ""))
end

function go_downstairs(confirm)
    magic(">" .. (confirm and "Y" or ""))
end

function plan_go_to_transporter()
    if unable_to_travel()
            or not want_to_use_transporters()
            or transp_search then
        return false
    end

    local search_count
    if in_branch("Gauntlet") then
        -- Maps can have functionally different types of transporter routes
        -- and always start the player closest to a route of one type, so
        -- randomize which of the starting transporters we choose. No Gauntlet
        -- map has more than 3 starting transporters, and most have two, so
        -- use '>' 1 to 4 times to reduce bias.
        if transp_zone == 0 then
            search_count = crawl.roll_dice(1, 4)
        -- After the first transporter, always take the closest one. This is
        -- important for gammafunk_gauntlet_77_escape_option so we don't take
        -- the early exit after each portal.
        else
            search_count = 1
        end
    else
        search_count = 1
        while transp_map[transp_zone]
                and transp_map[transp_zone][search_count] do
            search_count = search_count + 1
        end
    end

    transp_search_zone = transp_zone
    transp_search_count = search_count
    magic("X" .. (">"):rep(search_count) .. "\r")
    return true
end

function plan_transporter_orient_exit()
    if unable_to_move() or not transp_orient then
        return false
    end

    magic("X<\r")
    return true
end

function unable_to_use_transporters()
    return unable_to_move() or you.mesmerised()
end

function plan_enter_transporter()
    if not transp_search
            or view.feature_at(0, 0) ~= "transporter"
            or unable_to_use_transporters() then
        return false
    end

    magic(">")
    return true
end

function plan_take_unexplored_stairs()
    if not goal_travel.stairs_dir or unable_to_use_stairs() then
        return false
    end

    local feat = view.feature_at(0, 0)
    local dir, num = stone_stairs_type(feat)
    if not dir or dir ~= goal_travel.stairs_dir then
        return false
    end

    local state = get_stone_stairs(where_branch, where_depth, dir, num)
    if state.feat >= const.explore.explored then
        return false
    end

    -- Ensure that we autoexplore any new area we arrive in, otherwise, if we
    -- have completed autoexplore at least once, we may immediately leave
    -- once we see we've found the last missing staircase.
    reset_autoexplore(where_branch, where_depth + dir)

    if dir == const.dir.up then
        go_upstairs()
    else
        go_downstairs()
    end
    return true
end

-- Backtrack to the previous level if we're trying to explore stairs on a
-- destination level yet have no further accessible unexplored stairs. We
-- require a travel stairs search direction to know whether to attempt this
-- and what direction we should backtrack. Stairs are reset in the relevant
-- directions on both levels so after we explore the pair of stairs used to
-- return to the previous level, we'll take a different set of stairs from
-- that level via a new travel stairs search direction.
function plan_unexplored_stairs_backtrack()
    if unable_to_travel() or goal_travel.want_go or not goal_travel.stairs_dir then
        return false
    end

    local next_depth = where_depth + goal_travel.stairs_dir
    reset_stone_stairs(where_branch, where_depth, goal_travel.stairs_dir)
    reset_stone_stairs(where_branch, next_depth, -goal_travel.stairs_dir)
    send_travel(where_branch, next_depth)
    return true
end

function unable_to_use_stairs()
    return unable_to_move() or you.mesmerised()
end

function count_stair_followers(radius)
    return count_enemies(radius,
        function (mons)
            return mons:can_seek() and mons:can_use_stairs()
        end)
end

function plan_take_upstairs()
    if not want_to_take_upstairs()
            or unable_to_use_stairs()
            or dangerous_to_move(true) then
        return false
    end

    go_upstairs(you.status("spiked"))
    return true
end

function teleporting_before_dangerous_stairs()
    if goal_travel.want_go or not goal_travel.safe_stairs then
        return false
    end

    local feat = view.feature_at(0, 0)
    if feat ~= goal_travel.safe_stairs then
        return false
    end

    local state = get_destination_stairs(where_branch, where_depth, feat)
    local threat = 0
    if state then
        threat = state.threat
    elseif where_branch == "Vaults"
            and where_depth == branch_depth("Vaults") - 1 then
        threat = 25
    end
    return threat >= extreme_threat_level()
end

function plan_teleport_dangerous_stairs()
    if not can_teleport() or not teleporting_before_dangerous_stairs() then
        return false
    end

    return teleport()
end

function plan_use_travel_stairs()
    if unable_to_use_stairs() or dangerous_to_move() then
        return false
    end

    local feat = view.feature_at(0, 0)
    if goal_travel.safe_hatch and not goal_travel.want_go then
        local map_pos = unhash_position(goal_travel.safe_hatch)
        if not positions_equal(qw.map_pos, map_pos)
                or feat ~= "escape_hatch_down" then
            return false
        end
    else
        local feats = goal_travel_features()
        if not feats then
            return false
        end

        if not util.contains(feats, feat) then
            return false
        end
    end

    if feature_uses_map_key(">", feat) then
        go_downstairs()
        return true
    elseif feature_uses_map_key("<", feat) then
        go_upstairs()
        return true
    end

    return false
end

function plan_abort_safe_stairs()
    if goal_travel.want_go or not (goal_travel.safe_stairs or goal_travel.safe_hatch) then
        return false
    end

    -- We need to update goal travel ourself immediately because we also need
    -- to restart the cascade so that previous plans can do something besides
    -- attempting to use safe stairs.
    qw.safe_stairs_failed = true
    update_goal()

    qw.restart_cascade = true
    return true
end
