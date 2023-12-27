---------------------------------------------
-- Per-turn update and other turn-related aspects.

-- A value for sorting last when comparing turns.
const.inf_turns = 200000000

function turn_memo(name, func)
    if qw.turn_memos[name] == nil then
        local val = func()
        if val == nil then
            val = false
        end
        qw.turn_memos[name] = val
    end

    return qw.turn_memos[name]
end

function turn_memo_args(name, func, ...)
    assert(arg.n > 0)

    local parent, key
    for j = 1, arg.n do
        if j == 1 then
            parent = qw.turn_memos
            key = name
        end

        if parent[key] == nil then
            parent[key] = {}
        end

        parent = parent[key]

        key = arg[j]
        -- We turn any nil argument into false so we can pass on a valid set of
        -- args to the function. This might cause unexpected behaviour for an
        -- arbitrary function.
        if key == nil then
            key = false
            arg[j] = false
        end
    end

    if parent[key] == nil then
        local val = func(unpack(arg))
        if val == nil then
            val = false
        end
        parent[key] = val
    end

    return parent[key]
end

-- We want to call this exactly once each turn.
function turn_update()
    if not qw.initialized then
        initialize()
    end

    local turns = you.turns()
    if turns == qw.turn_count then
        qw.time_passed = false
        return
    end

    have_orb = you.have_orb()
    qw.time_passed = true
    qw.turn_count = turns
    qw.turn_memos = {}
    qw.attacks = nil

    if you.turns() >= qw.dump_count then
        dump_count = qw.dump_count + 100
        crawl.dump_char()
    end

    if qw.turn_count >= qw.skill_count then
        qw.skill_count = qw.skill_count + 5
        handle_skills()
    end

    if hp_is_full() then
        qw.full_hp_turn = qw.turn_count
    end
    position_is_safe = is_safe_at(const.origin)
    position_is_cloudy = not position_is_safe and view.cloud_at(0, 0) ~= nil

    if you.god() ~= previous_god then
        previous_god = you.god()
        want_goal_update = true
    end

    local new_level = false
    local full_map_clear = false
    if you.where() ~= where then
        new_level = previous_where ~= nil
        cache_parity = 3 - cache_parity

        if you.where() ~= previous_where and new_level then
            full_map_clear = true
        end

        previous_where = where
        where = you.where()
        where_branch = you.branch()
        where_depth = you.depth()
        want_goal_update = true

        can_retreat_upstairs = not (in_branch("D") and where_depth == 1
            or in_portal()
            or in_branch("Abyss")
            or in_branch("Pan")
            or in_branch("Tomb") and where_depth > 1
            or in_hell_branch(where_branch))
        base_corrosion = in_branch("Dis") and 2 or 0

        target_flee_position = nil
        transp_zone = 0
        stuck_turns = 0

        if at_branch_end("Vaults") and not vaults_end_entry_turn then
            vaults_end_entry_turn = qw.turn_count
        elseif where == "Tomb:2" and not tomb2_entry_turn then
            tomb2_entry_turn = qw.turn_count
        elseif where == "Tomb:3" and not tomb3_entry_turn then
            tomb3_entry_turn = qw.turn_count
        end
    end

    if have_orb and where == zot_end then
        ignore_traps = true
    else
        ignore_traps = false
    end

    base_corrosion = base_corrosion
        + count_adjacent_slimy_walls_at(const.origin)

    if you.flying() then
        gained_permanent_flight = permanent_flight == false
            and not temporary_flight
        if gained_permanent_flight then
            want_goal_update = true
        end

        permanent_flight = not temporary_flight
    else
        permanent_flight = false
        temporary_flight = false
    end

    update_monsters()

    update_map(new_level, full_map_clear)

    danger = sense_danger(qw.los_radius)
        or not map_is_unexcluded_at(qw.map_pos)
    immediate_danger = sense_immediate_danger()

    update_move_destination()
    update_flee_positions()
    update_reachable_position()
    update_reachable_features()

    if want_goal_update then
        update_goal()

        if goal_status == "Save" or goal_status == "Quit" then
            return
        end
    end

    if not c_persist.zig_completed
            and in_branch("Zig")
            and where_depth == goal_zig_depth(goal_status) then
        c_persist.zig_completed = true
    end

    if qw.enemy_memory and qw.enemy_memory_turns_left > 0 then
        qw.enemy_memory_turns_left = qw.enemy_memory_turns_left - 1
    end
    choose_tactical_step()

    map_mode_search_attempts = 0
end
