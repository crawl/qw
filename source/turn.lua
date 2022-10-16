---------------------------------------------
-- per-turn update and ready function

INF_TURNS = 200000000

function stop()
    automatic = false
    unset_options()
end

function start()
    automatic = true
    set_options()
    ready()
end

function panic(msg)
    crawl.mpr("<lightred>" .. msg .. "</lightred>")
    stop()
end

function startstop()
    if automatic then
        stop()
    else
        start()
    end
end

function set_waypoint()
    magic(control('w') .. waypoint_parity)
    did_waypoint = true
    return true
end

function set_options()
    crawl.setopt("pickup_mode = multi")
    crawl.setopt("message_colour += mute:Search for what")
    crawl.setopt("message_colour += mute:Can't find anything")
    crawl.setopt("message_colour += mute:Drop what")
    crawl.setopt("message_colour += mute:Okay, then")
    crawl.setopt("message_colour += mute:Use which ability")
    crawl.setopt("message_colour += mute:Read which item")
    crawl.setopt("message_colour += mute:Drink which item")
    crawl.setopt("message_colour += mute:not good enough")
    crawl.setopt("message_colour += mute:Attack whom")
    crawl.setopt("message_colour += mute:move target cursor")
    crawl.setopt("message_colour += mute:Aim:")
    crawl.setopt("message_colour += mute:You reach to attack")
    crawl.enable_more(false)
end

function unset_options()
    crawl.setopt("pickup_mode = auto")
    crawl.setopt("message_colour -= mute:Search for what")
    crawl.setopt("message_colour -= mute:Can't find anything")
    crawl.setopt("message_colour -= mute:Drop what")
    crawl.setopt("message_colour -= mute:Okay, then")
    crawl.setopt("message_colour -= mute:Use which ability")
    crawl.setopt("message_colour -= mute:Read which item")
    crawl.setopt("message_colour -= mute:Drink which item")
    crawl.setopt("message_colour -= mute:not good enough")
    crawl.setopt("message_colour -= mute:Attack whom")
    crawl.setopt("message_colour -= mute:move target cursor")
    crawl.setopt("message_colour -= mute:Aim:")
    crawl.setopt("message_colour -= mute:You reach to attack")
    crawl.enable_more(true)
end

-- We want to call this exactly once each turn.
function turn_update()
    if not initialized then
        initialize()
    end

    if you.turns() == old_turn_count then
        time_passed = false
        return
    end

    time_passed = true
    old_turn_count = you.turns()
    if you.turns() >= dump_count then
        dump_count = dump_count + 100
        crawl.dump_char()
    end

    if you.turns() >= skill_count then
        skill_count = skill_count + 5
        handle_skills()
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

    if you.where() ~= where then
        if (where == "nowhere" or is_waypointable(where))
                and is_waypointable(you.where()) then
            waypoint_parity = 3 - waypoint_parity

            if you.where() ~= previous_where or in_branch("Tomb") then
                clear_level_map(waypoint_parity)
                set_waypoint()
                coroutine.yield()
            end

            current_where = you.where()
            previous_where = where
        elseif is_waypointable(you.where())
                and you.where() ~= current_where then
            clear_level_map(waypoint_parity)
            set_waypoint()
            coroutine.yield()
            current_where = you.where()
        end

        where = you.where()
        where_branch = you.branch()
        where_depth = you.depth()
        want_gameplan_update = true

        target_stair = nil
        transp_zone = 0
        zone_counts = {}

        clear_ignores()
        stuck_turns = 0

        base_corrosion = in_branch("Dis") and 2 or 0

        if you.have_orb() and where == zot_end then
            ignore_traps = true
        else
            ignore_traps = false
        end

        if at_branch_end("Vaults") and not vaults_end_entry_turn then
            vaults_end_entry_turn = you.turns()
        elseif where == "Tomb:2" and not tomb2_entry_turn then
            tomb2_entry_turn = you.turns()
        elseif where == "Tomb:3" and not tomb3_entry_turn then
            tomb3_entry_turn = you.turns()
        end
    end

    transp_search = nil
    if can_use_transporters() then
        local feat = view.feature_at(0, 0)
        if feat_uses_map_key(">", feat) and map_search_zone then
            if not zone_counts[map_search_zone] then
                zone_counts[map_search_zone] = {}
            end
            zone_counts[map_search_zone][map_search_count] = transp_zone
            map_search_zone = nil
            map_search_count = nil
            if feat == "transporter" then
                transp_search = transp_zone
            end
        elseif feat == "exit_" .. where_branch:lower() then
            transp_zone = 0
            transp_orient = false
        end
    end

    can_waypoint = is_waypointable(where)
    if can_waypoint then
        update_level_map(waypoint_parity)
    end

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
    map_search_attempts = 0

    update_monster_array()
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

function run_update()
    if update_coroutine == nil then
        update_coroutine = coroutine.create(turn_update)
    end

    local okay, err = coroutine.resume(update_coroutine)
    if not okay then
        error("Error in coroutine: " .. err)
    end

    if coroutine.status(update_coroutine) == "dead" then
        update_coroutine = nil
        do_dummy_action = false
    else
        do_dummy_action = true
    end
end

function ready()
    run_update()
    if do_dummy_action then
        if not did_waypoint then
            crawl.process_keys(":" .. string.char(27) .. string.char(27))
        else
            did_waypoint = false
        end
        return
    end
    if time_passed and SINGLE_STEP then
        stop()
    end
    if automatic then
        crawl.flush_input()
        crawl.more_autoclear(true)
        if have_message then
            plan_message()
        elseif you.branch() == "Abyss" then
            plan_abyss_move()
        elseif you.have_orb() then
            plan_orbrun_move()
        else
            plan_move()
        end
    end
end
