----------------------
-- Stair-related plans

function go_upstairs(confirm)
    magic("<" .. (confirm and "Y" or ""))
end

function go_downstairs(confirm)
    magic(">" .. (confirm and "Y" or ""))
end

function plan_go_to_unexplored_stairs()
    if unable_to_travel()
            or goal_travel.want_go
            or not goal_travel.stairs_dir then
        return false
    end

    if map_mode_search_attempts == 1 then
        map_mode_search_attempts = 0
        disable_autoexplore = false
        return false
    end

    local key = dir_key(goal_travel.stairs_dir)
    local hash = hash_position(global_pos)
    local searches = map_mode_searches[key]
    local count = 1
    while searches and searches[hash] and searches[hash][count] do
        -- Trying to go one past this count lands us at the same destination as
        -- the count, so there are no more accessible unexplored stairs to be
        -- found from where we are, and we stop the search. The backtrack plan
        -- can take over from here.
        if searches[hash][count] == searches[hash][count + 1] then
            return false
        end

        count = count + 1
    end

    map_mode_search_key = key
    map_mode_search_hash = hash
    map_mode_search_count = count
    map_mode_search_attempts = 1
    magic("X" .. key:rep(count) .. "\r")
end

function plan_go_to_transporter()
    if unable_to_travel()
            or not want_to_use_transporters()
            or transp_search then
        return false
    end

    local search_count
    if in_branch("Gauntlet") then
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
    assert(state, "Stone stairs at current position with undefined state")
    if state.feat >= const.feat_state.explored then
        return false
    end

    -- Ensure that we autoexplore any new area we arrive in, otherwise, if we
    -- have completed autoexplore at least once, we may immediately leave once
    -- we see we've found the last missing staircase.
    reset_autoexplore(make_level(where_branch, where_depth + dir))

    if dir == const.dir.up then
        go_upstairs()
    else
        go_downstairs()
    end
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
    if unable_to_travel()
            or goal_travel.want_go
            or not goal_travel.stairs_dir then
        return false
    end

    local next_depth = where_depth + goal_travel.stairs_dir
    reset_stone_stairs(where_branch, where_depth, goal_travel.stairs_dir)
    reset_stone_stairs(where_branch, next_depth, -goal_travel.stairs_dir)
    send_travel(where_branch, next_depth)
    return true
end

function plan_go_to_upstairs()
    magic("X<\r")
    return true
end

function unable_to_use_stairs()
    return unable_to_move() or you.mesmerised()
end

function want_to_stairdance_up()
    local feat = view.feature_at(0, 0)
    if not can_retreat_upstairs or not feature_is_upstairs(feat) then
        return false
    end

    if in_bad_form() then
        return true
    end

    local state = get_destination_stairs(where_branch, where_depth, feat)
    if state and not state.safe then
        return false
    end

    local n = stairdance_count[where] or 0
    if n >= 20 then
        return false
    end

    if you.caught()
            or you.constricted()
            or count_brothers_in_arms(3) > 0
            or count_greater_servants(3) > 0
            or count_divine_warriors(3) > 0 then
        return false
    end

    local only_when_safe = you.berserk() or hp_is_low(33)
    local follow_count = 0
    local other_count = 0
    for _, enemy in ipairs(enemy_list) do
        if enemy:distance() == 1
                and enemy:stabbability() == 0
                and enemy:can_use_stairs() then
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
                    -- Makes Delver take upstairs immediately rather than stay
                    -- and fight incoming monsters that .
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
    if not unable_to_use_stairs() and want_to_stairdance_up() then
        say("STAIRDANCE")
        go_upstairs(you.status("spiked"))
        return true
    end

    return false
end

-- It's dangerous to hatch through unexplored areas in Zot as opposed
-- to simply taking an explored route through stone stairs. So we only
-- take a hatch up in Zot if the destination level is fully explored.
function want_to_use_escape_hatches(dir)
    return dir == const.dir.up
        and goal_status == "Escape"
        and not branch_is_temporary(where_branch)
        and not in_branch("Tomb")
        and where_depth > 1
            and (where_branch ~= "Zot"
                or explored_level(where_branch, where_depth - 1))
end

function plan_take_escape_hatch()
    local dir = escape_hatch_type(view.feature_at(0, 0))
    if not dir
            or not want_to_use_escape_hatches(dir)
            or unable_to_use_stairs() then
        return false
    end

    if dir == const.dir.up then
        go_upstairs()
    else
        go_downstairs()
    end

    return true
end

function plan_move_towards_escape_hatch()
    if want_to_use_escape_hatches(const.dir.up) then
        return false
    end

    local flee_pos = best_flee_destination_at(const.origin)
    if not flee_pos then
        return false
    end

    if not c_persist.up_hatches[hash_position(flee_pos)] then
        return false
    end

    local result = best_move_towards(flee_pos, true)
    if result then
        return move_to(result.move)
    end

    return false
end
