------------------
-- The exploration plan cascades.

function plan_move_towards_safety()
    if autoexplored_level(where_branch, where_depth)
            or disable_autoexplore
            or position_is_safe
            or unable_to_move()
            or dangerous_to_move()
            or you.mesmerised() then
        return false
    end

    local move, dest = best_move_towards_safety()
    if move then
        if debug_channel("explore") then
            dsay("Moving to safe position at "
                .. cell_string_from_map_position(dest))
        end
        return move_towards_destination(move, dest, "safety")
    end

    return false
end

function plan_autoexplore()
    if unable_to_travel()
            or disable_autoexplore
            or free_inventory_slots() == 0 then
        return false
    end

    magic("o")
    return true
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

function unable_to_travel()
    return danger or position_is_cloudy or unable_to_move()
end

function plan_go_to_portal_entrance()
    if unable_to_travel()
            or in_portal()
            or not is_portal_branch(goal_branch)
            or not branch_found(goal_branch) then
        return false
    end

    local desc = portal_entrance_description(goal_branch)
    -- For timed bazaars, make a search string that can' match permanent
    -- ones.
    if goal_branch == "Bazaar" and not permanent_bazaar then
        desc = "a flickering " .. desc
    end
    magicfind(desc)
    return true
end

-- Use the 'G' command to travel to our next destination.
function plan_go_command()
    if unable_to_travel() or not goal_travel.want_go then
        return false
    end

    if goal_status == "Escape"
            and goal_travel.branch == "D"
            and goal_travel.depth == 1 then
        send_travel("D", 0)
    else
        send_travel(goal_travel.branch, goal_travel.depth)
    end
    return true
end

function plan_go_to_portal_exit()
    -- Zig has its own stair handling in plan_zig_go_to_stairs().
    if unable_to_travel() or not in_portal() or where_branch == "Zig" then
        return false
    end

    magic("X<\r")
    return true
end

-- Open runed doors in Pan to get to the pan lord vault and open them on levels
-- that are known to contain entrances to Pan if we intend to visit Pan.
function plan_open_runed_doors()
    if not open_runed_doors then
        return false
    end

    for pos in adjacent_iter(const.origin) do
        if view.feature_at(pos.x, pos.y) == "runed_clear_door" then
            magic(delta_to_vi(pos) .. "Y")
            return true
        end
    end
    return false
end

function plan_enter_portal()
    if not is_portal_branch(goal_branch)
            or view.feature_at(0, 0) ~= branch_entrance(goal_branch)
            or unable_to_use_stairs() then
        return false
    end

    go_downstairs(goal_branch == "Zig", true)
    return true
end

function plan_exit_portal()
    if not in_portal()
            -- Zigs have their own exit rules.
            or where_branch == "Zig"
            or view.feature_at(0, 0) ~= branch_exit(where_branch)
            or unable_to_use_stairs() then
        return false
    end

    local parent, depth = parent_branch(where_branch)
    remove_portal(make_level(parent, depth), where_branch, true)

    go_upstairs()
    return true
end

function plan_use_goal_feature()
    if unable_to_use_stairs() or dangerous_to_move() then
        return false
    end

    local feats = goal_travel_features()
    local feat = view.feature_at(0, 0)
    if not util.contains(feats, feat) then
        return false
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

function plan_move_towards_goal_feature()
    if unable_to_move() or dangerous_to_move() then
        return false
    end

    local feats = goal_travel_features()
    if util.contains(feats, view.feature_at(0, 0)) then
        return false
    end

    local move, dest = best_move_towards_features(feats)
    if move then
        return move_towards_destination(move, dest, "goal")
    end

    move, dest = best_move_towards_features(feats, true)
    if move then
        return move_towards_destination(move, dest, "goal")
    end

    local god = goal_god(goal_status)
    if not god then
        return false
    end

    if c_persist.altars[god] and c_persist.altars[god][where] then
        for hash, _ in pairs(c_persist.altars[god][where]) do
            if update_altar(god, where, hash,
                    { feat = const.feat_state.seen }, true) then
                restart_cascade = true
            end
        end
    end

    return false
end

function plan_move_towards_destination()
    if not move_destination or dangerous_to_move() then
        return false
    end

    local move = best_move_towards_map_position(move_destination)
    if move then
        return move_to(move)
    end

    local move = best_move_towards_map_position(move_destination, true)
    if move then
        return move_to(move)
    end

    return false
end

function plan_move_towards_monster()
    if not position_is_safe or unable_to_move() or dangerous_to_move() then
        return false
    end

    local mons_targets = {}
    for _, enemy in ipairs(enemy_list) do
        table.insert(mons_targets, position_sum(global_pos, enemy:pos()))
    end

    if #mons_targets == 0 then
        for pos in square_iter(const.origin) do
            local mons = monster.get_monster_at(pos.x, pos.y)
            if mons and Monster:new(mons):is_enemy() then
                table.insert(mons_targets, position_sum(global_pos, pos))
            end
        end
    end

    if #mons_targets == 0 then
        return false
    end

    local move, dest = best_move_towards_map_positions(mons_targets)
    if move then
        if debug_channel("explore") then
            dsay("Moving to enemy at "
                .. cell_string_from_map_position(dest))
        end
        return move_towards_destination(move, dest, "monster")
    end

    return false
end

function plan_move_towards_unexplored()
    if disable_autoexplore or unable_to_move() or dangerous_to_move() then
        return false
    end

    local move, dest = best_move_towards_unexplored()
    if move then
        if debug_channel("explore") then
            dsay("Moving to explore near "
                .. cell_string_from_map_position(dest))
        end
        return move_towards_destination(move, dest, "unexplored")
    end

    return false
end

function plan_swamp_clear_exclusions()
    if not at_branch_end("Swamp") then
        return false
    end

    magic("X" .. control('e'))
    return true
end

function plan_swamp_go_to_rune()
    if not at_branch_end("Swamp") or have_branch_runes("Swamp") then
        return false
    end

    if last_swamp_fail_count
            == c_persist.plan_fail_count.try_swamp_go_to_rune then
        swamp_rune_reachable = true
    end

    last_swamp_fail_count = c_persist.plan_fail_count.try_swamp_go_to_rune
    magicfind("@" .. branch_runes("Swamp")[1] .. " rune")
    return true
end

function is_swamp_end_cloud(pos)
    return (view.cloud_at(pos.x, pos.y) == "freezing vapour"
            or view.cloud_at(pos.x, pos.y) == "foul pestilence")
        and you.see_cell_no_trans(pos.x, pos.y)
        and not is_safe_at(pos)
end

function plan_swamp_clouds_hack()
    if not at_branch_end("Swamp") then
        return false
    end

    if have_branch_runes("Swamp") and can_teleport() then
        return teleport()
    end

    if swamp_rune_reachable then
        say("Waiting for clouds to move.")
        wait_one_turn()
        return true
    end

    local best_pos
    local best_dist = 11
    for pos in adjacent_iter(const.origin) do
        if can_move_to(pos) and is_safe_at(pos) then
            for dpos in radius_iter(pos) do
                local dist = supdist(position_difference(dpos, pos))
                if is_swamp_end_cloud(dpos) and dist < best_dist then
                    best_pos = pos
                    best_dist = dist
                end
            end
        end
    end

    if best_pos then
        magic(delta_to_vi(best_pos) .. "Y")
        return true
    end

    for pos in square_iter(const.origin) do
        if (view.cloud_at(pos.x, pos.y) == "freezing vapour"
                    or view.cloud_at(pos.x, pos.y) == "foul pestilence")
                and you.see_cell_no_trans(pos.x, pos.y) then
            return random_step(where)
        end
    end

    return plan_stuck_teleport()
end

function plan_tomb_use_hatch()
    if (where == "Tomb:2" and not have_branch_runes("Tomb")
                or where == "Tomb:1")
            and view.feature_at(0, 0) == "escape_hatch_down" then
        prev_hatch_dist = 1000
        go_downstairs()
        return true
    end

    if (where == "Tomb:3" and have_branch_runes("Tomb")
                or where == "Tomb:2")
            and view.feature_at(0, 0) == "escape_hatch_up" then
        prev_hatch_dist = 1000
        go_upstairs()
        return true
    end

    return false
end

function plan_tomb_go_to_final_hatch()
    if where == "Tomb:2"
            and not have_branch_runes("Tomb")
            and view.feature_at(0, 0) ~= "escape_hatch_down" then
        magic("X>\r")
        return true
    end
    return false
end

function plan_tomb_go_to_hatch()
    if where == "Tomb:3"
            and have_branch_runes("Tomb")
            and view.feature_at(0, 0) ~= "escape_hatch_up" then
        magic("X<\r")
        return true
    elseif where == "Tomb:2" then
        if not have_branch_runes("Tomb")
                and view.feature_at(0, 0) == "escape_hatch_down" then
            return false
        end

        if view.feature_at(0, 0) == "escape_hatch_up" then
            local new_hatch_dist = supdist(global_pos)
            if new_hatch_dist >= prev_hatch_dist
                    and not positions_equal(global_pos, prev_hatch) then
                return false
            end

            prev_hatch_dist = new_hatch_dist
            prev_hatch = util.copy_table(global_pos)
        end

        magic("X<\r")
        return true
    elseif where == "Tomb:1" then
        if view.feature_at(0, 0) == "escape_hatch_down" then
            local new_hatch_dist = supdist(global_pos)
            if new_hatch_dist >= prev_hatch_dist
                    and not positions_equal(global_pos, prev_hatch) then
                return false
            end

            prev_hatch_dist = new_hatch_dist
            prev_hatch = util.copy_table(global_pos)
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


function set_plan_pre_explore()
    plans.pre_explore = cascade {
        {plan_ancestor_life, "ancestor_life"},
        {plan_sacrifice, "sacrifice"},
        {plans.acquirement, "acquirement"},
        {plan_bless_weapon, "bless_weapon"},
        {plan_upgrade_weapon, "upgrade_weapon"},
        {plan_use_good_consumables, "use_good_consumables"},
        {plan_unwield_weapon, "unwield_weapon"},
    }
end

function set_plan_pre_explore2()
    plans.pre_explore2 = cascade {
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
    plans.explore = cascade {
        {plan_dive_pan, "dive_pan"},
        {plan_dive_go_to_pan_downstairs, "try_dive_go_to_pan_downstairs"},
        {plan_take_escape_hatch, "take_escape_hatch"},
        {plan_move_towards_escape_hatch, "try_go_to_escape_hatch"},
        {plan_move_towards_destination, "move_towards_destination"},
        {plan_move_towards_abyssal_rune, "move_towards_abyssal_rune"},
        {plan_move_towards_runelight, "move_towards_runelight"},
        {plan_move_towards_safety, "move_towards_safety"},
        {plan_autoexplore, "try_autoexplore"},
    }
end

function set_plan_explore2()
    plans.explore2 = cascade {
        {plan_abandon_god, "abandon_god"},
        {plan_use_altar, "use_altar"},
        {plan_go_to_altar, "try_go_to_altar"},
        {plan_enter_portal, "enter_portal"},
        {plan_go_to_portal_entrance, "try_go_to_portal_entrance"},
        {plan_open_runed_doors, "open_runed_doors"},
        {plan_enter_transporter, "enter_transporter"},
        {plan_transporter_orient_exit, "try_transporter_orient_exit"},
        {plan_go_to_transporter, "try_go_to_transporter"},
        {plan_exit_portal, "exit_portal"},
        {plan_go_to_portal_exit, "try_go_to_portal_exit"},
        {plan_shopping_spree, "try_shopping_spree"},
        {plan_swamp_clear_exclusions, "try_swamp_clear_exclusions"},
        {plan_swamp_go_to_rune, "try_swamp_go_to_rune"},
        {plan_swamp_clouds_hack, "swamp_clouds_hack"},
        {plan_tomb_go_to_final_hatch, "try_tomb_go_to_final_hatch"},
        {plan_tomb_go_to_hatch, "try_tomb_go_to_hatch"},
        {plan_tomb_use_hatch, "tomb_use_hatch"},
        {plan_enter_pan, "enter_pan"},
        {plan_go_to_pan_portal, "try_go_to_pan_portal"},
        {plan_exit_pan, "exit_pan"},
        {plan_go_to_pan_exit, "try_go_to_pan_exit"},
        {plan_go_down_pan, "try_go_down_pan"},
        {plan_go_to_pan_downstairs, "try_go_to_pan_downstairs"},
        {plan_enter_abyss, "enter_abyss"},
        {plan_go_to_abyss_portal, "try_go_to_abyss_portal"},
        {plan_go_down_abyss, "go_down_abyss"},
        {plan_move_to_zigfig_location, "try_move_to_zigfig_location"},
        {plan_use_zigfig, "use_zigfig"},
        {plan_zig_dig, "zig_dig"},
        {plan_go_to_zig_dig, "try_go_to_zig_dig"},
        {plan_zig_leave_level, "zig_leave_level"},
        {plan_zig_go_to_stairs, "try_zig_go_to_stairs"},
        {plan_take_unexplored_stairs, "take_unexplored_stairs"},
        {plan_go_to_unexplored_stairs, "try_go_to_unexplored_stairs"},
        {plan_go_to_orb, "try_go_to_orb"},
        {plan_go_command, "try_go_command"},
        {plan_use_goal_feature, "use_goal_feature"},
        {plan_move_towards_goal_feature, "move_towards_goal_feature"},
        {plan_autoexplore, "try_autoexplore2"},
        {plan_move_towards_monster, "move_towards_monster"},
        {plan_move_towards_unexplored, "move_towards_unexplored"},
        {plan_unexplored_stairs_backtrack, "try_unexplored_stairs_backtrack"},
    }
end
