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

    local new_level
    local clear_map = false
    if you.where() ~= where then
        new_level = true
        cache_parity = 3 - cache_parity

        if you.where() ~= previous_where then
            clear_map = true
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

        target_stair = nil
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

    if you.have_orb() and where == zot_end then
        ignore_traps = true
    else
        ignore_traps = false
    end

    update_monsters()
    update_map(new_level, clear_map)

    if want_gameplan_update then
        update_gameplan()
    end

    if not c_persist.zig_completed
            and in_branch("Zig")
            and where_depth == gameplan_zig_depth(gameplan_status) then
        c_persist.zig_completed = true
    end

    if turns_left_moving_towards_enemy > 0 then
        turns_left_moving_towards_enemy = turns_left_moving_towards_enemy - 1
    else
        enemy_memory = nil
    end

    danger = sense_danger(los_radius)
    immediate_danger = sense_immediate_danger()
    moving_unsafe = nil
    melee_unsafe = nil
    melee_target = nil

    if move_destination then
        local reset = false
        if move_reason == "monster" then
            local pos = position_difference(move_destination, global_pos)
            if supdist(pos) <= los_radius
                    and you.see_cell_no_trans(pos.x, pos.y) then
                reset = true
            end
        elseif global_pos.x == move_destination.x
                and global_pos.y == move_destination.y then
            reset = true
        end

        if reset then
            move_destination = nil
            move_reason = nil
        end
    end

    if danger then
        move_destination = nil
        move_reason = nil
    end

    find_good_stairs()

    choose_tactical_step()

    cloudy = not view.is_safe_square(0, 0) and view.cloud_at(0, 0) ~= nil
    go_travel_attempts = 0
    stash_travel_attempts = 0
    map_mode_search_attempts = 0
end
