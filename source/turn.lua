---------------------------------------------
-- Per-turn update and other turn-related aspects.

-- A value for sorting last when comparing turns.
const.inf_turns = 200000000

function turn_memo(func)
    local val = qw.turn_memos[func]
    if val == nil then
        val = func()
        if val == nil then
            val = false
        end
        qw.turn_memos[func] = val
    end

    return val
end

function turn_memo_args(func, ...)
    local args = table.pack(...)
    assert(args.n > 0)

    local parent, key
    for j = 1, args.n do
        if j == 1 then
            parent = qw.turn_memos
            key = func
        end

        local child = parent[key]
        if child == nil then
            child = {}
            parent[key] = child
        end
        parent = child

        key = args[j]
        if key == nil then
            key = false
        -- A position table. The position hash is the key.
        elseif type(key) == "table" then
            key = key.hash
        end
    end

    -- Obtain the actual value for this combination of arguments.
    local val = parent[key]
    if val == nil then
        val = func(...)
        if val == nil then
            val = false
        end
        parent[key] = val
    end

    return val
end

function reset_cached_turn_data(force)
    local turns = you.turns()
    if not force and qw.last_turn_reset == turns then
        return
    end

    qw.turn_memos = {}
    qw.autopickup_cache = {}
    qw.best_equip = nil
    qw.attacks = nil
    qw.flee_positions = nil
    qw.want_to_kite = nil
    qw.want_to_kite_step = nil

    qw.safe_stairs_failed = false

    qw.last_turn_reset = turns
end

-- We call this exactly once each turn, unless force is true.
function turn_update(force)
    if not qw.initialized then
        initialize()
    end

    local turns = you.turns()
    qw.time_passed = qw.turns and turns ~= qw.turns
    if qw.turns and not qw.time_passed and not force then
        return
    end

    qw.los_radius = you.los()
    qw.have_orb = you.have_orb()
    qw.turns = turns

    -- This is not normally reset during a turn update, but when forcing,
    -- which is often used in Wizard Mode, we want to reset it.
    if force then
        qw.retreat_result = nil
        qw.retreat_turns = nil
    end

    reset_cached_turn_data(true)

    update_equip_tracking()

    if turns >= qw.dump_count then
        dump_count = qw.dump_count + 100
        crawl.dump_char()
    end

    if turns >= qw.skill_count then
        qw.skill_count = qw.skill_count + 5
        handle_skills()
    end

    if hp_is_full() then
        qw.full_hp_turn = turns
    end

    if you.god() ~= previous_god then
        previous_god = you.god()
        qw.want_goal_update = true
    end

    local new_level = false
    local clear_cache = false
    local current_where = you.where()
    if current_where ~= where then
        new_level = previous_where ~= nil
        qw.cache.slot = 3 - qw.cache.slot

        -- The map cache at this slot is invalid, since it's not for the
        -- level we're loading, so clear it. When a game is started or
        -- resumed, this will also ensure that the slot is intialized.
        if current_where ~= previous_where then
            clear_cache = true
        end

        previous_where = where
        where = current_where
        where_branch = you.branch()
        where_depth = you.depth()
        qw.want_goal_update = true

        qw.can_flee_upstairs = not (in_branch("D") and where_depth == 1
            or in_portal()
            or in_branch("Abyss")
            or in_branch("Pan")
            or in_branch("Tomb") and where_depth > 1
            or in_hell_branch(where_branch))
        qw.last_flee_turn = nil

        qw.base_corrosion = in_branch("Dis") and 8 or 0
        transp_zone = 0
        qw.stuck_turns = 0

        if at_branch_end("Vaults") and not vaults_end_entry_turn then
            vaults_end_entry_turn = turns
        elseif where == "Tomb:2" and not tomb2_entry_turn then
            tomb2_entry_turn = turns
        elseif where == "Tomb:3" and not tomb3_entry_turn then
            tomb3_entry_turn = turns
        end
    end

    if qw.have_orb and where == zot_end then
        qw.ignore_traps = true
    else
        qw.ignore_traps = false
    end

    update_map(new_level, clear_cache)

    qw.base_corrosion = qw.base_corrosion
        + 4 * count_slimy_walls_at(const.origin)

    if you.flying() then
        qw.gained_permanent_flight = qw.permanent_flight == false
            and not qw.temporary_flight
        if qw.gained_permanent_flight then
            qw.want_goal_update = true
        end

        qw.permanent_flight = not qw.temporary_flight
    else
        qw.permanent_flight = false
        qw.temporary_flight = false
    end

    qw.position_is_safe = is_safe_at(const.origin)
    qw.position_is_cloudy = not qw.position_is_safe
        and not cloud_is_safe(view.cloud_at(0, 0))

    qw.danger_in_los = #qw.enemy_list > 0
        or map_is_excluded_at(qw.map_pos)
    qw.immediate_danger = check_immediate_danger()

    update_move_destination()

    if qw.want_goal_update then
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

    if qw.last_enemy_memory_turns
            and qw.turns - qw.last_enemy_memory_turns > 10 then
        qw.last_enemy_memory_pos = nil
        qw.last_enemy_memory_turns = nil
    end

    choose_tactical_step()
end
