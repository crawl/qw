---------------------------------------------
-- Per-turn update and other turn-related aspects.

-- A value for sorting last when comparing turns.
INF_TURNS = 200000000

function turn_memo(name, func)
    if memos[name] == nil then
        memos[name] = func()
    end

    return memos[name]
end

-- We want to call this exactly once each turn.
function turn_update()
    if not initialized then
        initialize()
    end

    local turns = you.turns()
    if turns == turn_count then
        time_passed = false
        return
    end

    have_orb = you.have_orb()
    time_passed = true
    turn_count = turns
    memos = {}
    if you.turns() >= dump_count then
        dump_count = dump_count + 100
        crawl.dump_char()
    end

    if turn_count >= skill_count then
        skill_count = skill_count + 5
        handle_skills()
    end

    if hp_is_full() then
        full_hp_turn = turn_count
    end
    position_is_safe = view.is_safe_square(0, 0)
    position_is_cloudy = not position_is_safe and view.cloud_at(0, 0) ~= nil

    local new_level = false
    local full_map_clear = false
    if you.where() ~= where then
        new_level = true
        cache_parity = 3 - cache_parity

        if you.where() ~= previous_where then
            full_map_clear = true
        end

        previous_where = where
        where = you.where()
        where_branch = you.branch()
        where_depth = you.depth()
        want_gameplan_update = true

        can_retreat_upstairs = not (in_branch("D") and where_depth == 1
            or in_portal()
            or in_branch("Abyss")
            or in_branch("Pan")
            or in_branch("Tomb") and where_depth > 1
            or in_hell_branch(where_branch))
        base_corrosion = in_branch("Dis") and 2 or 0

        local pan_parent, min_depth, max_depth = parent_branch("Pan")
        open_runed_doors = in_branch("Abyss")
            or in_branch("Pan")
            or in_portal()
            or planning_pan
                and in_branch(pan_parent)
                and where_depth >= min_depth
                and where_depth <= max_depth

        target_flee_position = nil
        transp_zone = 0

        stuck_turns = 0

        if at_branch_end("Vaults") and not vaults_end_entry_turn then
            vaults_end_entry_turn = turn_count
        elseif where == "Tomb:2" and not tomb2_entry_turn then
            tomb2_entry_turn = turn_count
        elseif where == "Tomb:3" and not tomb3_entry_turn then
            tomb3_entry_turn = turn_count
        end
    end

    if have_orb and where == zot_end then
        ignore_traps = true
    else
        ignore_traps = false
    end

    base_corrosion = base_corrosion
        + (adjacent_slimy_walls_at(origin) and 1 or 0)

    if you.flying() then
        gained_permanent_flight = permanent_flight == false
            and not temporary_flight
        if gained_permanent_flight then
            want_gameplan_update = true
        end

        permanent_flight = not temporary_flight
    else
        permanent_flight = false
        temporary_flight = false
    end

    update_monsters()

    update_map(new_level, full_map_clear)
    update_move_destination()
    update_flee_positions()
    update_reachable_position()
    update_reachable_features()

    if want_gameplan_update then
        update_gameplan()
    end

    if not c_persist.zig_completed
            and in_branch("Zig")
            and where_depth == gameplan_zig_depth(gameplan_status) then
        c_persist.zig_completed = true
    end

    danger = sense_danger(los_radius) or not map_is_unexcluded_at(global_pos)
    immediate_danger = sense_immediate_danger()

    if turns_left_moving_towards_enemy > 0 then
        turns_left_moving_towards_enemy = turns_left_moving_towards_enemy - 1
    end
    melee_target = nil
    choose_tactical_step()

    map_mode_search_attempts = 0
end
