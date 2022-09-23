function plan_autoexplore()
    if disable_autoexplore
            -- Autoexplore will try to take us near any runed doors. We don't
            -- even attempt it if doing a stairs search, since it would move us
            -- off our map travel destination.
            or stairs_search
            or free_inventory_slots() == 0 then
        return false
    end

    magic("o")
    return true
end

function add_ignore(dx, dy)
    local m = monster_array[dx][dy]
    if not m then
        return
    end

    local name = m:name()
    if not util.contains(ignore_list, name) then
        table.insert(ignore_list, name)
        crawl.setopt("runrest_ignore_monster ^= " .. name .. ":1")
        if DEBUG_MODE then
            dsay("Ignoring " .. name .. ".")
        end
    end
end

function remove_ignore(dx, dy)
    local m = monster_array[dx][dy]
    local name = m:name()
    for i, mname in ipairs(ignore_list) do
        if mname == name then
            table.remove(ignore_list, i)
            crawl.setopt("runrest_ignore_monster -= " .. name .. ":1")
            if DEBUG_MODE then
                dsay("Unignoring " .. name .. ".")
            end
            return
        end
    end
end

function clear_ignores()
    local size = #ignore_list
    local mname
    if size > 0 then
        for i = 1, size do
            mname = table.remove(ignore_list)
            crawl.setopt("runrest_ignore_monster -= " .. mname .. ":1")
            dsay("Unignoring " .. mname .. ".")
        end
    end
end

function send_travel(branch, depth)
    local depth_str
    if depth == nil or branch_depth(branch) == 1 then
        depth_str = ""
    else
        depth_str = depth
    end

    magic("G" .. branch_travel(branch) .. depth_str .. "\rY")
end

function plan_go_to_portal_entrance()
    if in_portal()
            or not is_portal_branch(gameplan_branch)
            or not branch_found(gameplan_branch)
            or cloudy then
        return false
    end

    if stash_travel_fail_count == 0 then
        local desc = portal_entrance_description(gameplan_branch)
        -- For timed bazaars, make a search string that can' match permanent
        -- ones.
        if gameplan_branch == "Bazaar" and not permanent_bazaar then
            desc = "a flickering " .. desc
        end
        magicfind(desc)

        stash_travel_fail_count = 1
        return
    end

    stash_travel_fail_count = 0
    disable_autoexplore = false
    return false
end

-- Use the 'G' command to travel to our next destination.
function plan_go_command()
    if not want_go_travel or cloudy then
        return false
    end

    if go_travel_fail_count == 0 then
        go_travel_fail_count = 1
        send_travel(travel_branch, travel_depth)
        return
    end

    go_travel_fail_count = 0
    disable_autoexplore = false
    return false
end

function plan_go_to_portal_exit()
    -- Zig has its own stair handling in plan_zig_go_to_stairs().
    if in_portal() and where_branch ~= "Zig" then
        magic("X<\r")
        return true
    end

    return false
end

-- Open runed doors in Pan to get to the pan lord vault and open them on levels
-- that are known to contain entrances to Pan if we intend to visit Pan.
function plan_open_runed_doors()
    if not in_branch("Pan") and not in_branch("Abyss") and not in_portal() then
        local br, min_depth, max_depth = parent_branch("Pan")
        if where_branch ~= parent_branch("Pan")
                or where_depth < min_depth
                or where_depth > max_depth
                or not planning_pan then
            return false
        end
    end

    for x = -1, 1 do
        for y = -1, 1 do
            if view.feature_at(x, y) == "runed_clear_door" then
                magic(delta_to_vi(x, y) .. "Y")
                return true
            end
        end
    end
    return false
end

function plan_enter_portal()
    if not is_portal_branch(gameplan_branch)
            or view.feature_at(0, 0) ~= branch_entrance(gameplan_branch) then
        return false
    end

    magic(">" .. (gameplan_branch == "Zig" and "Y" or ""))
    return true
end

function plan_exit_portal()
    if not in_portal()
            -- Zigs have their own exit rules.
            or gameplan_branch == "Zig"
            or you.mesmerised()
            or not view.feature_at(0, 0):find("exit_" .. where:lower()) then
        return false
    end

    local parent, depth = parent_branch(where_branch)
    remove_portal(make_level(parent, depth), where_branch, true)

    magic("<")
    return true
end

function set_plan_pre_explore()
    plan_pre_explore = cascade {
        {plan_ancestor_life, "ancestor_life"},
        {plan_sacrifice, "sacrifice"},
        {plan_handle_acquirement_result, "handle_acquirement_result"},
        {plan_bless_weapon, "bless_weapon"},
        {plan_upgrade_weapon, "upgrade_weapon"},
        {plan_use_good_consumables, "use_good_consumables"},
    }
end

function set_plan_pre_explore2()
    plan_pre_explore2 = cascade {
        {plan_disturbance_random_step, "disturbance_random_step"},
        {plan_upgrade_armour, "upgrade_armour"},
        {plan_upgrade_amulet, "upgrade_amulet"},
        {plan_upgrade_rings, "upgrade_rings"},
        {plan_read_id, "try_read_id"},
        {plan_quaff_id, "quaff_id"},
        {plan_use_id_scrolls, "use_id_scrolls"},
        {plan_drop_other_items, "drop_other_items"},
        {plan_full_inventory_panic, "full_inventory_panic"},
    }
end

function set_plan_explore()
    plan_explore = cascade {
        {plan_dive_pan, "dive_pan"},
        {plan_dive_go_to_pan_downstairs, "try_dive_go_to_pan_downstairs"},
        {plan_autoexplore, "try_autoexplore"},
    }
end

function set_plan_explore2()
    plan_explore2 = cascade {
        {plan_abandon_god, "abandon_god"},
        {plan_join_god, "try_join_god"},
        {plan_find_altar, "try_find_altar"},
        {plan_convert, "convert"},
        {plan_find_conversion_altar, "try_find_conversion_altar"},
        {plan_move_to_zigfig_location, "try_move_to_zigfig_location"},
        {plan_use_zigfig, "try_use_zigfig"},
        {plan_zig_dig, "zig_dig"},
        {plan_go_to_zig_dig, "try_go_to_zig_dig"},
        {plan_enter_portal, "enter_portal"},
        {plan_go_to_portal_entrance, "try_go_to_portal_entrance"},
        {plan_open_runed_doors, "open_runed_doors"},
        {plan_enter_transporter, "enter_transporter"},
        {plan_transporter_orient_exit, "try_transporter_orient_exit"},
        {plan_go_to_transporter, "try_go_to_transporter"},
        {plan_zig_leave_level, "zig_leave_level"},
        {plan_zig_go_to_stairs, "try_zig_go_to_stairs"},
        {plan_exit_portal, "exit_portal"},
        {plan_go_to_portal_exit, "try_go_to_portal_exit"},
        {plan_enter_pan, "enter_pan"},
        {plan_go_to_pan_portal, "try_go_to_pan_portal"},
        {plan_exit_pan, "exit_pan"},
        {plan_go_to_pan_exit, "try_go_to_pan_exit"},
        {plan_go_down_pan, "try_go_down_pan"},
        {plan_go_to_pan_downstairs, "try_go_to_pan_downstairs"},
        {plan_enter_abyss, "enter_abyss"},
        {plan_go_to_abyss_portal, "try_go_to_abyss_portal"},
        {plan_go_to_unexplored_stairs, "try_go_to_unexplored_stairs"},
        {plan_take_unexplored_stairs, "try_take_unexplored_stairs"},
        {plan_shopping_spree, "try_shopping_spree"},
        {plan_go_to_orb, "try_go_to_orb"},
        {plan_go_command, "try_go_command"},
        {plan_autoexplore, "try_autoexplore2"},
        {plan_unexplored_stairs_backtrack, "try_unexplored_stairs_backtrack"},
    }
end

-- Hook to determine which traps are safe to move over without requiring an
-- answer to a yesno prompt. We currently only disable permanent teleport and
-- dispersal traps by default since these can create infinite movement loops as
-- we repeatedly move onto them without having -Tele somehow. This can be
-- conditionally disabled with ignore_traps, e.g. as we do on Zot:5.
-- XXX: We ideally would have more robust logic that wouldn't have us move on
-- Zot traps unless we really needed to.
function c_trap_is_safe(trap)
    return you.race() == "Formicid"
        or ignore_traps
        or trap ~= "permanent teleport" and trap ~= "dispersal"
end