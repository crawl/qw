------------------
-- The common plan functions and the overall turn plan.

function use_ability(name, extra, mute)
    for letter, abil in pairs(you.ability_table()) do
        if abil == name then
            -- Want to make sure we don't get a skill selection screen if we
            -- were training Dodging.
            if name == "Sacrifice Nimbleness" then
                you.train_skill("Fighting", 1)
            end

            if not mute then
                say("INVOKING " .. name .. ".")
            end

            magic("a" .. letter .. (extra or ""))
            return true
        end
    end

    return false
end

-- This plan is called outside of the turn plan cascade.
function plan_message()
    if qw.read_message then
        crawl.setopt("clear_messages = false")
        magic("_")
        qw.read_message = false
    else
        crawl.setopt("clear_messages = true")
        magic(":qwqwqw\r")
        qw.read_message = true
        qw.have_message = false
        crawl.delay(2500)
    end
end

function plan_save()
    if goal_status == "Save" then
        c_persist.last_completed_goal = goal_status
        magic(control("s"))
        return true
    end

    return false
end

function plan_quit()
    if goal_status == "Quit" then
        c_persist.last_completed_goal = goal_status
        magic(control('q') .. "yes\r")
        return true
    end

    return false
end

-----------------------------------------
-- Every plan function that might take an action should return as follows:
--   true if tried to do something.
--   false if didn't do anything.
--   nil if should be rerun. This can be used when a plan might fail to consume
--   a turn, allowing the plan to attempt a fallback actions. Plans returning
--   nil must track their function calls carefully with an appropriate
--   variable, otherwise they'll create an infinite loop.

-- This is the bot's flowchart for using plan functions.
function cascade(plans)
    local plan_turns = {}
    local plan_result = {}
    return function ()
        for i, plandata in ipairs(plans) do
            local plan = plandata[1]
            if plan == nil then
                error("No plan function for " .. plandata[2])
            end

            if qw.restart_cascade
                    or you.turns() ~= plan_turns[plan]
                    or plan_result[plan] == nil then
                local result = plan()
                if not qw.automatic then
                    return true
                end

                plan_turns[plan] = you.turns()
                plan_result[plan] = result

                if debug_channel("plans") and result ~= false
                        or debug_channel("plans-all") then
                    dsay("Ran " .. plandata[2] .. ": " .. tostring(result))
                end

                if result == nil or result == true then
                    if qw.delayed and result == true then
                        crawl.delay(next_delay)
                    end
                    next_delay = qw.delay_time

                    return
                end
            elseif plan_turns[plan] and plan_result[plan] == true then
                if not plandata[2]:find("^try") then
                    panic(plandata[2] .. " failed despite returning true.")
                end

                local fail_count = c_persist.plan_fail_count[plandata[2]]
                if not fail_count then
                    fail_count = 0
                end
                fail_count = fail_count + 1
                c_persist.plan_fail_count[plandata[2]] = fail_count

                if qw.want_goal_update then
                    update_goal()
                end
            end
        end

        return false
    end
end

function initialize_plan_cascades()
    set_plan_emergency()
    set_plan_attack()
    set_plan_rest()
    set_plan_acquirement()
    set_plan_pre_explore()
    set_plan_pre_explore2()
    set_plan_explore()
    set_plan_explore2()
    set_plan_stuck()
    set_plan_turn()
end

-- This is the main turn planning cascade.
function set_plan_turn()
    plans.turn = cascade {
        {plan_save, "save"},
        {plan_quit, "quit"},
        {plan_ancestor_identity, "try_ancestor_identity"},
        {plan_join_beogh, "join_beogh"},
        {plan_shop, "shop"},
        {plans.emergency, "emergency"},
        {plans.attack, "attack"},
        {plans.rest, "rest"},
        {plans.pre_explore, "pre_explore"},
        {plans.explore, "explore"},
        {plans.pre_explore2, "pre_explore2"},
        {plans.explore2, "explore2"},
        {plans.stuck, "stuck"},
    }
end
