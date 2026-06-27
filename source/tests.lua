--------------------
-- Testing functions

function wiz_command(command, want_return)
    qw.do_dummy_action = false
    magic("&" .. command .. (want_return and "\r" or ""))
    coroutine.yield()
end

function clear_level_data(branch, depth)
    local level = make_level(branch, depth)
    if debug_channel("map") then
        dsay("Clearing level data for " .. level)
    end

    -- Waypoint creation requires accurate where information, so temporarily
    -- set this to the target level.
    local current_where = where
    where = level
    update_waypoint(true, true)
    where = current_where

    local level = make_level(branch, depth)
    if branch_is_connected(branch) then
        if level == zot_end then
            c_persist.zot5 = {}
        end

        c_persist.upstairs[level] = nil
        c_persist.downstairs[level] = nil
        c_persist.up_hatches[level] = nil
        c_persist.down_hatches[level] = nil
    elseif branch == "Pan" then
        c_persist.pan_transits = {}
    elseif branch == "Abyss" then
        c_persist.abyssal_stairs = {}
    end
end

function wiz_make_scenario_item(item)
    local num = 1
    if item.num then
        num = item.num
    end

    local count = count_item(item.class, item.subtype, item.ego)
    if count >= num then
        return
    end

    local item_spec
    if item.class == "missile" or item.class == "misc" then
        item_spec = item.subtype
        if item.ego then
            item_spec = item_spec .. " ego:" .. item.ego
        end
    else
        item_spec = item.class .. " of " .. item.subtype
    end

    if num > 1 then
        item_spec = item_spec .. " q:" .. num - count
    end

    wiz_command("%" .. item_spec, true)
end

function run_scenario(scenario)
    qw.scenario.count = qw.scenario.count + 1
    say("Scenario " .. qw.scenario.name .. " trial #" .. qw.scenario.count)

    -- Full heal and remove runes/orb.
    wiz_command("H")
    wiz_command("Z")

    -- Default to full piety.
    if scenario.piety then
        wiz_command("^" .. tostring(scenario.piety), true)
    else
        wiz_command("^200", true)
    end

    if scenario.items then
        for _, item in ipairs(scenario.items) do
            wiz_make_scenario_item(item)
        end

        -- We don't want any monsters preventing us from picking up items.
        if not you.feel_safe() then
            wiz_command("Glos", true)
        end

        qw.do_dummy_action = false
        magic(";")
        coroutine.yield()
    end

    override_goal(scenario.goal)
    local branch, min_depth, max_depth = parse_level_range(goal_status)
    if not branch then
        branch = goal_branch
        min_depth = goal_depth
        max_depth = goal_depth
    end

    -- Regenerate each level in the goal range, doing so in reverse so we end
    -- up at the start of the range.
    for i = max_depth, min_depth, -1 do
        wiz_command("~" .. branch_data[branch].symbol .. i, true)

        -- Make sure to kill any active tesseract so we don't maintain the
        -- tesseract status.
        if branch == "Zot" and i == branch_depth(branch) then
            wiz_command("Gtesseract", true)
        end

        wiz_command("*R")
        clear_level_data(branch, i)
    end

    clear_map_cache(1)
    clear_map_cache(2)

    -- If possible, we go up to the level before the start of our goal so that
    -- we can properly play the first turn of the goal.
    if branch_is_connected(branch)
            and not (branch == "D" and min_depth == 1) then
        wiz_command("u")
    end

    start(false)
end

function start_scenario(name, trials)
    if not qw.scenarios[name] then
        error("Unknown scenario: " .. name)
    end

    if not trials then
        trials = 1
    end
    assert(trials > 0)

    qw.override_goal = nil
    qw.scenario = {
        name = name,
        def = qw.scenarios[name],
        trials = trials,
        count = 0,
        deaths = 0,
    }
end

function handle_scenario()
    -- If we still have an override goal, a scenario trial is ongoing.
    if not qw.scenario or qw.override_goal then
        return
    end

    local running = qw.scenario.count < qw.scenario.trials
    if running then
        run_scenario(qw.scenario.def)
    end

    if running and qw.scenario.count == 1 then
        sayf("Running scenario %s for %d trials",
            qw.scenario.name,
            qw.scenario.trials)
    else
        local success = qw.scenario.count - qw.scenario.deaths
        sayf("%s results for scenario %s: %d/%d (%.2f%%)",
            running and "Current" or "Final",
            qw.scenario.name,
            success,
            qw.scenario.count,
            100 * success / qw.scenario.count)
    end

    if not running then
        qw.scenario = nil
    end

    say("Hit TAB to continue")
    stop()
end
