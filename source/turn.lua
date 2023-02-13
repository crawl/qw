---------------------------------------------
-- Per-turn update and other turn-related aspects.

-- A value for sorting last when comparing turns.
INF_TURNS = 200000000

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

    local new_waypoint = false
    if you.where() ~= where then
        new_waypoint = update_waypoint_data()

        if you.where() ~= previous_where or new_waypoint then
            clear_map_data(waypoint_parity)
        end
        previous_where = where
        where = you.where()
        where_branch = you.branch()
        where_depth = you.depth()
        want_gameplan_update = true

        level_has_upstairs = not in_portal()
            and not in_branch("Abyss")
            and not in_branch("Pan")
            and (not in_branch("Tomb") or where_depth == 1)
            and not in_hell_branch(where_branch)
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
        zone_counts = {}

        stuck_turns = 0

        if you.have_orb() and where == zot_end then
            ignore_traps = true
        else
            ignore_traps = false
        end

        if at_branch_end("Vaults") and not vaults_end_entry_turn then
            vaults_end_entry_turn = turn_count
        elseif where == "Tomb:2" and not tomb2_entry_turn then
            tomb2_entry_turn = turn_count
        elseif where == "Tomb:3" and not tomb3_entry_turn then
            tomb3_entry_turn = turn_count
        end
    end

    if did_move then
        move_count = move_count + 1
    else
        move_count = 0
    end

    did_move = false
    if did_move_towards_monster > 0 then
        did_move_towards_monster = did_move_towards_monster - 1
    end

    transp_search = nil
    if can_use_transporters() then
        local feat = view.feature_at(0, 0)
        if feature_uses_map_key(">", feat) and transp_search_zone then
            if not transp_map[transp_search_zone] then
                transp_map[transp_search_zone] = {}
            end
            transp_map[transp_search_zone][transp_search_count] = transp_zone
            transp_search_zone = nil
            transp_search_count = nil
            if feat == "transporter" then
                transp_search = transp_zone
            end
        elseif feat == "exit_" .. where_branch:lower() then
            transp_zone = 0
            transp_orient = false
        end
    end

    handle_exclusions(new_waypoint)
    update_map_data()

    if want_gameplan_update then
        update_gameplan()
    end

    if not c_persist.zig_completed
            and in_branch("Zig")
            and where_depth == gameplan_zig_depth(gameplan_status) then
        c_persist.zig_completed = true
    end

    go_travel_attempts = 0
    stash_travel_attempts = 0
    map_mode_search_attempts = 0

    update_monster_map()
    danger = sense_danger(los_radius)
    immediate_danger = sense_immediate_danger()
    sense_sigmund()
    find_good_stairs()

    cloudy = not view.is_safe_square(0, 0) and view.cloud_at(0, 0) ~= nil
    choose_tactical_step()

    if collectgarbage("count") > 7000 then
        collectgarbage()
    end
end
