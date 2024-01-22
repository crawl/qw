------------------
-- Start of game and session initialization.

function cleanup_feature_state(state)
    if state.safe == nil then
        state.safe = true
    end
    if state.feat == nil then
        state.feat = const.explore.none
    end
end

function cleanup_feature_table(feat_table, table_level)
    for key, inner_table in pairs(feat_table) do
        if table_level == 1 then
            cleanup_feature_state(inner_table)
        else
            cleanup_feature_table(inner_table, table_level - 1)
        end
    end
end

function cleanup_c_persist_features()
    cleanup_feature_table(c_persist.upstairs, 2)
    cleanup_feature_table(c_persist.downstairs, 2)

    cleanup_feature_table(c_persist.branch_exits, 2)
    cleanup_feature_table(c_persist.branch_entries, 2)

    cleanup_feature_table(c_persist.up_hatches, 2)
    cleanup_feature_table(c_persist.down_hatches, 2)

    cleanup_feature_table(c_persist.altars, 3)

    cleanup_feature_table(c_persist.abyssal_stairs, 1)
end

function initialize_c_persist()
    if not c_persist.waypoint_count then
        c_persist.waypoint_count = 0
    end

    local tables = {
        "abyssal_stairs", "altars", "autoexplore", "branch_entries",
        "branch_exits", "down_hatches", "downstairs", "exclusions",
        "expiring_portals", "pan_transits", "plan_fail_count", "portals",
        "potion_ident", "scroll_ident", "seen_items",
        "up_hatches", "upstairs", "waypoints",
    }
    for _, table in ipairs(tables) do
        if not c_persist[table] then
            c_persist[table] = {}
        end
    end

    cleanup_c_persist_features()
end

function initialize_rc_variables()
    qw.max_memory = MAX_MEMORY
    qw.max_memory_percentage = MAX_MEMORY_PERCENTAGE
    qw.coroutine_throttle = COROUTINE_THROTTLE

    qw.delayed = DELAYED
    qw.delay_time = DELAY_TIME

    qw.single_step = SINGLE_STEP
    if AUTO_START then
        qw.automatic = true
    end

    qw.quit_turns = QUIT_TURNS
    qw.wizmode_death = WIZMODE_DEATH

    qw.combo_cycle = COMBO_CYCLE
    qw.combo_cycle_list = COMBO_CYCLE_LIST
    qw.goals = GOALS
    qw.default_goal = DEFAULT_GOAL

    qw.god_list = GOD_LIST
    qw.faded_altar = FADED_ALTAR
    qw.ck_abandon_xom = CK_ABANDON_XOM

    qw.allowed_portals = ALLOWED_PORTALS
    qw.early_second_rune = EARLY_SECOND_RUNE
    qw.late_orc = LATE_ORC
    qw.rune_preference = RUNE_PREFERENCE

    qw.shield_crazy = SHIELD_CRAZY
    qw.full_inventory_panic = FULL_INVENTORY_PANIC
end

function initialize_enums()
    const.autoexplore = enum(const.autoexplore)
    const.explore = enum(const.explore)
    const.map_select = enum(const.map_select)
    const.attitude = enum(const.attitude)
    const.duration = enum(const.duration)
end

function initialize_const()
    initialize_enums()
    initialize_player_durations()
    initialize_ego_damage()
end

function initialize()
    -- The version of qw for logging purposes. Run the make-qw.sh script to set
    -- this variable automatically based on the latest annotated git tag and
    -- commit, or change it here to a custom version string.
    qw.version = "%VERSION%"

    initialize_rc_variables()

    -- We don't want to hit max_memory since that will delete the c_persist
    -- table. Generally qw only gets clua memory usage above 32MB due to bugs.
    -- Leave some memory left over so we can avoid deleting c_persist as well
    -- as reset the coroutine and attempt debugging.
    if qw.max_memory and qw.max_memory_percentage then
        set_memory_limit(qw.max_memory * qw.max_memory_percentage / 100)
    end

    initialize_debug()
    initialize_const()
    initialize_plan_cascades()
    initialize_c_persist()

    if not cache_parity then
        traversal_maps_cache = {}
        adjacent_floor_maps_cache = {}
        exclusion_maps_cache = {}

        distance_maps_cache = {}
        feature_map_positions_cache = {}
        item_map_positions_cache = {}
        map_mode_searches_cache = {}

        clear_map_cache(1, true)
        clear_map_cache(2, true)

        cache_parity = 1
    end

    if you.turns() == 0 then
        initialize_branch_data()
        initialize_god_data()
    end

    initialize_branch_data()
    initialize_god_data()

    first_turn_initialize()
    initialize_c_persist()

    note_qw_data()

    calc_los_radius()
    initialize_monster_map()

    initialize_goals()
    starting_spell = get_starting_spell()

    set_options()

    clear_autopickup_funcs()
    add_autopickup_func(autopickup)

    qw.turn_count = you.turns() - 1
    qw.dump_count = you.turns() + 100 - (you.turns() % 100)
    qw.skill_count = you.turns() - (you.turns() % 5)
    qw.read_message = true

    qw.incoming_monsters_turn = -1
    qw.full_hp_turn = -1

    qw.initialized = true
end

function note_qw_data()
    note("qw: Version: " .. qw.version)
    note("qw: Game counter: " .. c_persist.record.counter)
    note("qw: Melee chars always use a shield: " .. bool_string(qw.shield_crazy))

    if not util.contains(god_options(), you.god()) then
        note("qw: God list: " .. table.concat(god_options(), ", "))
        note("qw: Allow faded altars: " .. bool_string(qw.faded_altar))
    end

    note("qw: Do Orc after clearing Dungeon:" .. branch_depth("D") .. " "
        .. bool_string(qw.late_orc))
    note("qw: Do second Lair branch before Depths: " ..
        bool_string(qw.early_second_rune))
    note("qw: Lair rune preference: " .. qw.rune_preference)
    note("qw: Goals: " .. goal_options())
end

function first_turn_initialize()
    if you.turns() > 0 and c_persist.record then
        return
    end

    if not c_persist.record then
        c_persist.record = {}
    end

    local counter = c_persist.record.counter
    if not counter then
        counter = 1
    else
        counter = counter + 1
    end
    c_persist.record.counter = counter

    local god_list = c_persist.next_god_list
    local goals = c_persist.next_goals
    for key, _ in pairs(c_persist) do
        if key ~= "record" then
            c_persist[key] = nil
        end
    end

    if not god_list then
        if qw.god_list and #qw.god_list > 0 then
            god_list = qw.god_list
        else
            error("No default god list defined in GOD_LIST rc variable.")
        end
    end

    -- Check for and normalize a list with "No God"
    local no_god = false
    for _, god in ipairs(god_list) do
        if god_full_name(god) == "No God" then
            no_god = true
            break
        end
    end
    if no_god then
        if #god_list > 1 then
            error("God list containing 'No God' must have no other entries.")
        else
            god_list = {"No God"}
        end
    end
    c_persist.current_god_list = god_list

    if not goals then
        goals = qw.default_goal
        if not goals then
            error("No default goal defined in DEFAULT_GOAL rc varaible.")
        end
    end
    c_persist.current_goals = goals

    if qw.combo_cycle then
        local combo_string_list = split(qw.combo_cycle_list, ",")
        local combo_string = combo_string_list[
            1 + (c_persist.record.counter % (#combo_string_list))]
        combo_string = trim(combo_string)
        local combo_parts = split(combo_string, "^")
        c_persist.options = "combo = " .. combo_parts[1]
        if #combo_parts > 1 then
            local goal_parts = split(combo_parts[2], "!")
            c_persist.next_god_list = {}
            for g in goal_parts[1]:gmatch(".") do
                table.insert(c_persist.next_god_list, god_full_name(g))
            end
            if #goal_parts > 1 then
                if not qw.goals[goal_parts[2]] then
                    error("Unknown goal name '" .. goal_parts[2] .. "'"
                        ..  " given in combo spec '" .. combo_string .. "'")
                end
                c_persist.next_goals = goal_parts[2]
            end
        end
    end
end
