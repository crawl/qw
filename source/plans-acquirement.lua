------------------
-- Plans for the acquirement cascade.

function can_receive_okawaru_weapon()
    return not c_persist.okawaru_weapon_gifted
        and you.god() == "Okawaru"
        and you.piety_rank() >= 6
        and contains_string_in("Receive Weapon", you.abilities())
        and can_invoke()
end

function can_receive_okawaru_armour()
    return not c_persist.okawaru_armour_gifted
        and you.god() == "Okawaru"
        and you.piety_rank() >= 6
        and contains_string_in("Receive Armour", you.abilities())
        and can_invoke()
end

function can_invent_gizmo()
    return not c_persist.invented_gizmo
        and you.xl() >= 14
        and contains_string_in("Invent Gizmo", you.abilities())
end

function choose_acquirement(acquire_type)
    local acq_items = items.acquirement_items(acquire_type)
    local cur_equip = inventory_equip(const.inventory.equipped)
    for _, item in ipairs(acq_items) do
        local min_val, max_val = equip_value(item)
        say("Offered " .. item.name() .. " with min/max values "
            .. min_val .. "/" .. max_val)
    end

    local index = best_acquirement_index(acq_items)
    if index then
        if acquire_type ~= const.acquire.gizmo then
            qw.acquirement_pickup = true
        end

        say("ACQUIRING " .. acq_items[index].name())
        return index
    else
        say("GAVE UP ACQUIRING")
        return 1
    end
end

function c_choose_acquirement()
    return choose_acquirement(const.acquire.scroll)
end

function c_choose_okawaru_weapon()
    return choose_acquirement(const.acquire.okawaru_weapon)
end

function c_choose_okawaru_armour()
    return choose_acquirement(const.acquire.okawaru_armour)
end

function c_choose_coglin_gizmo()
    return choose_acquirement(const.acquire.gizmo)
end

function can_read_acquirement()
    return find_item("scroll", "acquirement") and can_read()
end

function plan_move_for_acquirement()
    if qw.danger_in_los
            or not qw.position_is_safe
            or not can_read_acquirement()
                and not can_receive_okawaru_weapon()
                and not can_receive_okawaru_armour()
            or not destroys_items_at(const.origin)
            or unable_to_move()
            or dangerous_to_move() then
        return false
    end

    for pos in radius_iter(const.origin, qw.los_radius) do
        local map_pos = position_sum(qw.map_pos, pos)
        if map_is_reachable_at(map_pos) and not destroys_items_at(pos) then
            local result = best_move_towards(map_pos)
            if result and move_to(result.move) then
                return true
            end
        end
    end

    return false
end

function plan_receive_okawaru_weapon()
    if qw.danger_in_los
            or not qw.position_is_safe
            or not can_receive_okawaru_weapon() then
        return false
    end

    if use_ability("Receive Weapon") then
        c_persist.okawaru_weapon_gifted = true
        return true
    end

    return false
end

function plan_receive_okawaru_armour()
    if qw.danger_in_los
            or not qw.position_is_safe
            or not can_receive_okawaru_armour() then
        return false
    end

    if use_ability("Receive Armour") then
        c_persist.okawaru_armour_gifted = true
        return true
    end

    return false
end

function plan_invent_gizmo()
    if qw.danger_in_los
            or not qw.position_is_safe
            or not can_invent_gizmo() then
        return false
    end

    if use_ability("Invent Gizmo") then
        c_persist.invented_gizmo = true
        return true
    end

    return false
end

function plan_maybe_pickup_acquirement()
    if qw.acquirement_pickup then
        magic(",")
        qw.acquirement_pickup = false
        return true
    end

    return false
end

-- These plans will only execute after a successful acquirement.
function set_plan_acquirement()
    plans.acquirement = cascade {
        {plan_maybe_pickup_acquirement, "try_pickup_acquirement"},
        {plan_move_for_acquirement, "move_for_acquirement"},
        {plan_receive_okawaru_weapon, "receive_okawaru_weapon"},
        {plan_receive_okawaru_armour, "receive_okawaru_armour"},
        {plan_invent_gizmo, "invent_gizmo"},
    }
end
