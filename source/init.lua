------------------
-- Start of game and session initialization.

function initialize_c_persist()
    if not c_persist.waypoint_count then
        c_persist.waypoint_count = 0
    end

    local tables = {
        "waypoints", "exclusions", "portals", "branch_entries",
        "branch_exits", "altars", "autoexplore", "upstairs", "downstairs",
        "up_hatches", "down_hatches", "pan_transits", "abyssal_stairs",
        "runelights", "seen_items", "plan_fail_count"
    }
    for _, table in ipairs(tables) do
        if not c_persist[table] then
            c_persist[table] = {}
        end
    end
end

function initialize_enums()
    const.autoexplore = enum(const.autoexplore)
    const.feat_state = enum(const.feat_state)
    const.map_select = enum(const.map_select)
    const.attitude = enum(const.attitude)
end

function initialize()
    -- We don't want to hit max_memory since that will delete the c_persist
    -- table. Generally qw only gets clua memory usage above 32MB due to bugs.
    -- Leave some memory left over so we can avoid deleting c_persist as well
    -- as reset the coroutine and attempt debugging.
    if MAX_MEMORY then
        max_memory = MAX_MEMORY
    end
    if MAX_MEMORY_PERCENTAGE then
        max_memory_percentage = MAX_MEMORY_PERCENTAGE
    end
    if max_memory and max_memory_percentage then
        set_memory_limit(max_memory * max_memory_percentage / 100)
    end

    initialize_enums()
    initialize_debug()
    coroutine_throttle = COROUTINE_THROTTLE

    if you.turns() == 0 then
        initialize_c_persist()
        initialize_branch_data()
        initialize_god_data()
        first_turn_initialize()
    end

    initialize_c_persist()
    initialize_branch_data()
    initialize_god_data()

    calc_los_radius()
    initialize_monster_map()

    clear_autopickup_funcs()
    add_autopickup_func(autopickup)

    initialize_goals()

    if not cache_parity then
        traversal_maps_cache = {}
        exclusion_maps_cache = {}

        distance_maps_cache = {}
        feature_map_positions_cache = {}
        item_map_positions_cache = {}
        map_mode_searches_cache = {}

        clear_map_cache(1, true)
        clear_map_cache(2, true)

        cache_parity = 1
    end

    set_options()
    initialize_plans()
    initialized = true
end

function note_qw_data()
    note("qw: Version: " .. qw_version)
    note("qw: Game counter: " .. c_persist.record.counter)
    note("qw: Melee chars always use a shield: " .. bool_string(SHIELD_CRAZY))
    if not util.contains(god_options(), you.god()) then
        note("qw: God list: " .. table.concat(god_options(), ", "))
        note("qw: Allow faded altars: " .. bool_string(FADED_ALTAR))
    end
    note("qw: Do Orc after clearing Dungeon:" .. branch_depth("D") .. " "
        .. bool_string(LATE_ORC))
    note("qw: Do second Lair branch before Depths: " ..
        bool_string(EARLY_SECOND_RUNE))
    note("qw: Lair rune preference: " .. RUNE_PREFERENCE)

    local plans = goal_options()
    note("qw: Goals: " .. plans)
end

function first_turn_initialize()
    if AUTO_START then
        automatic = true
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
    local plans = c_persist.next_goals
    for key, _ in pairs(c_persist) do
        if key ~= "record" then
            c_persist[key] = nil
        end
    end

    if not god_list then
        if GOD_LIST and #GOD_LIST > 0 then
            god_list = GOD_LIST
        else
            error("No default god list defined in GOD_LIST.")
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

    c_persist.current_goals = plans
    note_qw_data()

    if COMBO_CYCLE then
        local combo_string_list = split(COMBO_CYCLE_LIST, ",")
        local combo_string = combo_string_list[
            1 + (c_persist.record.counter % (#combo_string_list))]
        combo_string = trim(combo_string)
        local combo_parts = split(combo_string, "^")
        c_persist.options = "combo = " .. combo_parts[1]
        if #combo_parts > 1 then
            local plan_parts = split(combo_parts[2], "!")
            c_persist.next_god_list = {}
            for g in plan_parts[1]:gmatch(".") do
                table.insert(c_persist.next_god_list, god_full_name(g))
            end
            if #plan_parts > 1 then
                if not GOALS[plan_parts[2]] then
                    error("Unknown plan name '" .. plan_parts[2] .. "'" ..
                    " given in combo spec '" .. combo_string .. "'")
                end
                c_persist.next_goals = plan_parts[2]
            end
        end
    end
end
