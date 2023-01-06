------------------
-- Plans for the Pandemonium branch.

function want_to_be_in_pan()
    return gameplan_branch == "Pan" and not have_branch_runes("Pan")
end

function plan_go_to_pan_portal()
    if in_branch("Pan")
            or not want_to_be_in_pan()
            or not branch_found("Pan")
            or cloudy then
        return false
    end

    if stash_travel_attempts == 0 then
        stash_travel_attempts = 1
        magicfind("halls of Pandemonium")
        return
    end

    stash_travel_attempts = 0
    disable_autoexplore = false
    return false
end

function plan_go_to_pan_downstairs()
    if in_branch("Pan") then
        magic("X>\r")
        return true
    end

    return false
end

local pan_failed_rune_count = -1
function want_to_dive_pan()
    return in_branch("Pan")
        and you.num_runes() > pan_failed_rune_count
        and (you.have_rune("demonic") and not have_branch_runes("Pan")
            or dislike_pan_level)
end

function plan_dive_go_to_pan_downstairs()
    if want_to_dive_pan() then
        magic("X>\r")
        return true
    end
    return false
end

function plan_go_to_pan_exit()
    if in_branch("Pan") and not want_to_be_in_pan() then
        magic("X<\r")
        return true
    end
    return false
end

function plan_enter_pan()
    if view.feature_at(0, 0) == "enter_pandemonium"
            and want_to_be_in_pan() then
        magic(">Y")
        return true
    end

    return false
end

local pan_stair_turn = -100
function plan_go_down_pan()
    if view.feature_at(0, 0) == "transit_pandemonium"
         or view.feature_at(0, 0) == "exit_pandemonium" then
        if pan_stair_turn == you.turns() then
            magic("X" .. control('f'))
            return true
        end
        pan_stair_turn = you.turns()
        magic(">Y")
        return nil -- in case we are trying to leave a rune level
    end
    return false
end

function plan_dive_pan()
    if not want_to_dive_pan() then
        return false
    end
    if view.feature_at(0, 0) == "transit_pandemonium"
         or view.feature_at(0, 0) == "exit_pandemonium" then
        if pan_stair_turn == you.turns() then
            pan_failed_rune_count = you.num_runes()
            return false
        end
        pan_stair_turn = you.turns()
        dislike_pan_level = false
        magic(">Y")
        -- In case we are trying to leave a rune level.
        return
    end
    return false
end

function plan_exit_pan()
    if view.feature_at(0, 0) == "exit_pandemonium"
            and not want_to_be_in_pan()
            and not you.mesmerised()
            and can_move() then
        magic("<")
        return true
    end

    return false
end
