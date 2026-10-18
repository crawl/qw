------------------
-- Plans specific to the Zot branch and the Orb run.

function tesseract_path_score(player_path)
    local trap_score = 0
    for _, pos in ipairs(player_path) do
        trap_score = trap_score + qw.trap_score_map[pos.hash]
    end

    if debug_channel("zot5") then
        dsay("Final trap score: " .. trap_score)
    end

    return trap_score
end

function assess_zot5_hall(hall)
    local result = { hall = hall }

    if debug_channel("zot5") then
        dsay("Evaluating tesseract position "
            .. cell_string_from_map_position(hall.tesseract_pos))
    end

    local player_path = move_path(const.move.safe_terrain, hall.tesseract_pos,
        true, c_persist.zot5.entry_pos)
    if not player_path then
        if debug_channel("zot5") then
            dsay("Invalid tesseract position: no valid path")
        end

        return
    end

    result.score = tesseract_path_score(player_path)
    if not result.score then
        return
    end

    return result
end

function best_zot5_hall()
    -- We cache the best hall calculation in c_persist because it won't change
    -- over turns and needs resetting if the c_persist zot5 data is reset.
    if c_persist.zot5.best_hall then
        return c_persist.zot5.best_hall
    end

    if debug_channel("zot5") then
        dsay("Calculating best Zot:5 hall")
    end

    local best_result
    for _, hall in ipairs(c_persist.zot5.halls) do
        local result = assess_zot5_hall(hall)
        if result
                and (not best_result or best_result.score > result.score) then
            best_result = result
        end
    end

    if not best_result then
        if debug_channel("zot5") then
            dsay("No valid Zot:5 hall found")
        end

        return
    end

    if debug_channel("zot5") then
        dsayf("Found best Zot:5 hall with tesseract at %s and trap score %d",
            cell_string_from_map_position(best_result.hall.tesseract_pos),
            best_result.score)
    end

    c_persist.zot5.best_hall = best_result.hall
    return best_result.hall
end

function plan_move_towards_tesseract()
    if not at_branch_end("Zot")
            or goal_status ~= "Tesseracts"
            or qw.danger_in_los
            or you.confused()
            or unable_to_move()
            or dangerous_to_move() then
        return false
    end

    local hall = best_zot5_hall()
    if not hall then
        return false
    end

    local result = best_move_towards(hall.tesseract_pos, true)
    if result then
        return move_towards_destination(result.move, result.dest_pos, "goal")
    end

    return false
end

function plan_move_towards_orb()
    if not at_branch_end("Zot")
            or goal_status ~= "Orb"
            or qw.danger_in_los
            or unable_to_move()
            or dangerous_to_move() then
        return false
    end

    local orb_dist = move_distance(const.move.safe_terrain,
        c_persist.zot5.orb_pos)

    if not orb_dist then
        return false
    end

    local hall = best_zot5_hall()
    if not hall then
        return false
    end

    local chamber_dist = move_distance(const.move.safe_terrain,
        hall.chamber_pos)
    if not chamber_dist or orb_dist < chamber_dist then
        result = best_move_towards(c_persist.zot5.orb_pos, true)
        if result then
            return move_towards_destination(result.move, result.dest_pos,
                "goal")
        end

        return false
    end

    local result = best_move_towards(hall.chamber_pos, true)
    if result then
        return move_towards_destination(result.move, result.dest_pos, "goal")
    end

    return false
end
