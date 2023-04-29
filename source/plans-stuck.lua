------------------
-- The normal plan cascade: choosing a move for a normal turn (not in the Abyss
-- or on the Orb run).

function plan_stuck_use_stairs()
    if dangerous_to_move() then
        return false
    end

    local feats = gameplan_features()
    local feat = view.feature_at(0, 0)
    if not feats or not util.contains(feats, feat) then
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

function plan_stuck_move_towards_gameplan()
    if dangerous_to_move() then
        return false
    end

    local move, dest = best_move_towards_gameplan()
    if move then
        move_to(move)
        return true
    end

    return false
end

function plan_stuck_move_towards_monster()
    if dangerous_to_move() then
        return false
    end

    local mons_targets = {}
    for _, enemy in ipairs(enemy_list) do
        table.insert(mons_targets, position_sum(global_pos, enemy:pos()))
    end

    if #mons_targets == 0 then
        for pos in square_iter(origin) do
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
            dsay("Moving to explore near "
                .. cell_string_from_map_position(dest))
        end
        move_to_destination(move, dest, "monster")
        return true
    end

    return false
end

function plan_stuck_move_towards_unexplored()
    if dangerous_to_move() then
        return false
    end

    move, dest = best_move_towards_unexplored()
    if move then
        if debug_channel("explore") then
            dsay("Moving to explore near "
                .. cell_string_from_map_position(dest))
        end
        move_to_destination(move, dest, "unexplored")
        return true
    end

    return false
end

function plan_exclusion_move_towards_unexcluded()
    if map_is_unexcluded_at(global_pos)
            or dangerous_to_move() then
        return false
    end

    move, dest = best_move_towards_unexcluded()
    if move then
        if debug_channel("explore") then
            dsay("Moving to unexcluded position at "
                .. cell_string_from_map_position(dest))
        end
        move_to_destination(dest, "unexcluded")
        return true
    end

    return false
end

function plan_stuck_random_step()
    stuck_turns = stuck_turns + 1
    return random_step("stuck")
end

function plan_stuck_initial()
    if stuck_turns <= 50 then
        return plan_stuck()
    end

    return false
end

function plan_stuck_clear_exclusions()
    local n = clear_exclusion_count[where] or 0
    if n > 20 then
        return false
    end

    clear_exclusion_count[where] = n + 1
    remove_exclusions(true)
    magic("X" .. control('e'))
    return true
end

function plan_stuck_dig_grate()
    local grate_offset = 20
    local grate_pos
    for pos in square_iter(origin) do
        if view.feature_at(pos.x, pos.y) == "iron_grate" then
            if abs(pos.x) + abs(pos.y) < grate_offset
                    and you.see_cell_solid_see(pos.x, pos.y) then
                grate_pos = pos
                grate_offset = abs(pos.x) + abs(pos.y)
            end
        end
    end

    if grate_offset < 20 then
        local c = find_item("wand", "digging")
        if c and can_zap() then
            say("ZAPPING " .. item(c).name() .. ".")
            magic("V" .. letter(c) .. "r" .. vector_move(grate_pos) .. "\r")
            return true
        end
    end

    return false
end

function plan_stuck_forget_map()
    if not cloudy
            and not danger
            and (at_branch_end("Slime") and not have_branch_runes("Slime")
                or at_branch_end("Geh") and not have_branch_runes("Geh")) then
        magic("X" .. control('f'))
        return true
    end
    return false
end

function plan_stuck_cloudy()
    if cloudy and not hp_is_low(50) and not you.mesmerised() then
        return random_step("cloudy")
    end
    return false
end

function plan_stuck_teleport()
    if can_teleport() then
        return teleport()
    end
    return false
end

function set_plan_stuck()
    plan_stuck = cascade {
        {plan_stuck_use_stairs, "stuck_use_stairs"},
        {plan_stuck_move_towards_gameplan, "stuck_move_towards_gameplan"},
        {plan_stuck_move_towards_monster, "stuck_move_towards_monster"},
        {plan_stuck_move_towards_unexplored, "stuck_move_towards_unexplored"},
        {plan_stuck_move_towards_unexcluded, "stuck_move_towards_unexcluded"},
        {plan_stuck_clear_exclusions, "try_stuck_clear_exclusions"},
        {plan_stuck_dig_grate, "try_stuck_dig_grate"},
        {plan_stuck_cloudy, "stuck_cloudy"},
        {plan_stuck_abyss_wait_one_turn, "stuck_abyss_wait_one_turn"},
        {plan_stuck_forget_map, "try_stuck_forget_map"},
        {plan_stuck_initial, "stuck_initial"},
        {plan_stuck_teleport, "stuck_teleport"},
        {plan_stuck_random_step, "stuck_random_step"},
    }
end
