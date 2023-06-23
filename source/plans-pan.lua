------------------
-- Plans specific to Pandemonium.

function want_to_be_in_pan()
    return goal_branch == "Pan" and not have_branch_runes("Pan")
end

function plan_go_to_pan_portal()
    if unable_to_travel()
            or in_branch("Pan")
            or not want_to_be_in_pan()
            or not branch_found("Pan") then
        return false
    end

    magicfind("halls of Pandemonium")
    return true
end

function plan_go_to_pan_downstairs()
    if not unable_to_travel() and in_branch("Pan") then
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
    if not unable_to_travel()
            and in_branch("Pan")
            and not want_to_be_in_pan() then
        magic("X<\r")
        return true
    end

    return false
end

function plan_enter_pan()
    if view.feature_at(0, 0) == branch_entrance("Pan")
            and want_to_be_in_pan()
            and not unable_to_use_stairs() then
        go_downstairs(true)
        return true
    end

    return false
end

local pan_stairs_turn = -100
function plan_go_down_pan()
    if view.feature_at(0, 0) ~= "transit_pandemonium"
                and view.feature_at(0, 0) ~= branch_exit("Pan")
            or unable_to_use_stairs() then
        return false
    end

    if pan_stairs_turn == you.turns() then
        magic("X" .. control('f'))
        return true
    end

    pan_stairs_turn = you.turns()
    go_downstairs(true)
    -- In case we are trying to leave a rune level.
    return nil
end

function plan_dive_pan()
    if not want_to_dive_pan() or unable_to_use_stairs() then
        return false
    end

    if view.feature_at(0, 0) == "transit_pandemonium"
            or view.feature_at(0, 0) == branch_exit("Pan") then
        if pan_stairs_turn == you.turns() then
            pan_failed_rune_count = you.num_runes()
            return false
        end

        pan_stairs_turn = you.turns()
        dislike_pan_level = false
        go_downstairs(true)
        -- In case we are trying to leave a rune level.
        return
    end

    return false
end

function plan_exit_pan()
    if view.feature_at(0, 0) == branch_exit("Pan")
            and not want_to_be_in_pan()
            and not unable_to_use_stairs() then
        go_upstairs()
        return true
    end

    return false
end
