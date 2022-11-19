function plan_go_to_unexplored_stairs()
    if not can_waypoint
            or not stairs_search_dir
            or where_branch ~= travel_branch
            or where_depth ~= travel_depth then
        return false
    end

    if map_search_attempts == 1 then
        map_search_attempts = 0
        disable_autoexplore = false
        return false
    end

    local key = dir_key(stairs_search_dir)
    local dx, dy = travel.waypoint_delta(waypoint_parity)
    local pos = 100 * dx + dy
    local map = map_search[waypoint_parity]
    local count = 1
    while map[key] and map[key][pos] and map[key][pos][count] do
        -- Trying to go one past this count lands us at the same destination as
        -- the count, so there are no more accessible unexplored stairs to be
        -- found from where we are, and we stop the search. The backtrack plan
        -- can take over from here.
        if map[key][pos][count] == map[key][pos][count + 1] then
            return false
        end

        count = count + 1
    end

    map_search_key = key
    map_search_pos = pos
    map_search_count = count
    map_search_attempts = 1
    magic("X" .. key:rep(count) .. "\r")
end

function can_use_transporters()
    return c_persist.autoexplore[where] == AUTOEXP.TRANSPORTER
        and (where_branch == "Temple" or in_portal())
end

function plan_go_to_transporter()
    if not can_use_transporters() or transp_search then
        return false
    end

    local search_count
    if where_branch == "Gauntlet" then
        -- Maps can have functionally different types of transporter routes and
        -- always start the player closest to a route of one type, so randomize
        -- which of the starting transporters we choose. No Gauntlet map has
        -- more than 3 starting transporters, and most have two, so use '>' 1
        -- to 4 times to reduce bias.
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
        while zone_counts[transp_zone]
                and zone_counts[transp_zone][search_count] do
            search_count = search_count + 1
        end
    end

    map_search_zone = transp_zone
    map_search_count = search_count
    magic("X" .. (">"):rep(search_count) .. "\r")
    return true
end

function plan_transporter_orient_exit()
    if not can_use_transporters() or not transp_orient then
        return false
    end

    magic("X<\r")
    return true
end

function plan_take_unexplored_stairs()
    if not stairs_search_dir then
        return false
    end

    local dir, num
    dir, num = stone_stair_type(view.feature_at(0, 0))
    if not dir or dir ~= stairs_search_dir
            or stairs_state(where_branch, where_depth, dir, num)
                >= FEAT_LOS.EXPLORED then
        return false
    end

    -- Ensure that we autoexplore any new area we arrive in, otherwise, if we
    -- have completed autoexplore at least once, we may immediately leave once
    -- we see we've found the last missing staircase.
    c_persist.autoexplore[make_level(where_branch, where_depth + dir)]
        = AUTOEXP.NEEDED

    magic("G" .. dir_key(dir))
    return true
end

-- Backtrack to the previous level if we're trying to explore stairs on a
-- destination level yet have no further accessible unexplored stairs. We
-- require a travel stairs search direction to know whether to attempt this and
-- what direction we should backtrack. Stairs are reset in the relevant
-- directions on both levels so after we explore the pair of stairs used to
-- return to the previous level, we'll take a different set of stairs from that
-- level via a new travel stairs search direction.
function plan_unexplored_stairs_backtrack()
    if not stairs_search_dir
            or where_branch ~= travel_branch
            or where_depth ~= travel_depth
            or cloudy then
        return false
    end

    local next_depth = where_depth + stairs_search_dir
    level_stair_reset(where_branch, where_depth, stairs_search_dir)
    level_stair_reset(where_branch, next_depth, -stairs_search_dir)
    want_gameplan_update = true
    send_travel(where_branch, next_depth)
    return true
end

function plan_find_upstairs()
    magic("X<\r")
    return true
end

function plan_enter_transporter()
    if not transp_search or view.feature_at(0, 0) ~= "transporter" then
        return false
    end

    magic(">")
    return true
end

function want_to_stairdance_up()
    if where == "D:1"
            or in_portal()
            or in_hell_branch()
            or in_branch("Abyss")
            or in_branch("Pan")
            or not feature_is_upstairs(view.feature_at(0, 0)) then
        return false
    end

    local n = stairdance_count[where] or 0
    if n >= 20 then
        return false
    end

    if you.caught()
            or you.mesmerised()
            or you.constricted()
            or not can_move()
            or count_bia(3) > 0
            or count_sgd(3) > 0
            or count_divine_warrior(3) > 0 then
        return false
    end

    local only_when_safe = you.berserk() or hp_is_low(33)
    local follow_count = 0
    local other_count = 0
    for _, e in ipairs(enemy_list) do
        if supdist(e.x, e.y) == 1
                and e.m:stabbability() == 0
                and can_use_stairs(e.m) then
            follow_count = follow_count + 1
        else
            other_count = other_count + 1
        end
    end

    if only_when_safe and follow_count > 0 then
        return false
    end

    if follow_count == 0
                and (reason_to_rest(90)
                    or you.xl() <= 8 and disable_autoexplore
                    or you.status("spiked"))
                and not buffed()
            or other_count > 0
                and follow_count > 0 then
        stairdance_count[where] = n + 1
        return true
    end

    return false
end

function plan_stairdance_up()
    if want_to_stairdance_up() then
        say("STAIRDANCE")
        if you.status("spiked") then
            magic("<Y")
        else
            magic("<")
        end
        return true
    end
    return false
end
