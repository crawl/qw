function plan_tomb_use_hatch()
    if (where == "Tomb:2" and not have_branch_runes("Tomb")
            or where == "Tomb:1")
         and view.feature_at(0, 0) == "escape_hatch_down" then
        prev_hatch_dist = 1000
        magic(">")
        return true
    end
    if (where == "Tomb:3" and have_branch_runes("Tomb")
            or where == "Tomb:2")
         and view.feature_at(0, 0) == "escape_hatch_up" then
        prev_hatch_dist = 1000
        magic("<")
        return true
    end
    return false
end

function plan_tomb_go_to_final_hatch()
    if where == "Tomb:2" and not have_branch_runes("Tomb")
         and view.feature_at(0, 0) ~= "escape_hatch_down" then
        magic("X>\r")
        return true
    end
    return false
end

function plan_tomb_go_to_hatch()
    if where == "Tomb:3" then
        if have_branch_runes("Tomb")
             and view.feature_at(0, 0) ~= "escape_hatch_up" then
            magic("X<\r")
            return true
        end
    elseif where == "Tomb:2" then
        if not have_branch_runes("Tomb")
             and view.feature_at(0, 0) == "escape_hatch_down" then
            return false
        end
        if view.feature_at(0, 0) == "escape_hatch_up" then
            local x, y = travel.waypoint_delta(waypoint_parity)
            local new_hatch_dist = supdist(x, y)
            if new_hatch_dist >= prev_hatch_dist
                 and (x ~= prev_hatch_x or y ~= prev_hatch_y) then
                return false
            end
            prev_hatch_dist = new_hatch_dist
            prev_hatch_x = x
            prev_hatch_y = y
        end
        magic("X<\r")
        return true
    elseif where == "Tomb:1" then
        if view.feature_at(0, 0) == "escape_hatch_down" then
            local x, y = travel.waypoint_delta(waypoint_parity)
            local new_hatch_dist = supdist(x, y)
            if new_hatch_dist >= prev_hatch_dist
                 and (x ~= prev_hatch_x or y ~= prev_hatch_y) then
                return false
            end
            prev_hatch_dist = new_hatch_dist
            prev_hatch_x = x
            prev_hatch_y = y
        end
        magic("X>\r")
        return true
    end
    return false
end

function plan_tomb2_arrival()
    if not tomb2_entry_turn
            or you.turns() >= tomb2_entry_turn + 5
            or c_persist.did_tomb2_buff then
        return false
    end

    if not you.hasted() then
        return haste()
    elseif not you.status("attractive") then
        if attraction() then
            c_persist.did_tomb2_buff = true
            return true
        end
        return false
    end
end

function plan_tomb3_arrival()
    if not tomb3_entry_turn
            or you.turns() >= tomb3_entry_turn + 5
            or c_persist.did_tomb3_buff then
        return false
    end

    if not you.hasted() then
        return haste()
    elseif not you.status("attractive") then
        if attraction() then
            c_persist.did_tomb3_buff = true
            return true
        end
        return false
    end
end
