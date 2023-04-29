------------------
-- Cascading plans common functions.

function magic(command)
    crawl.process_keys(command .. string.char(27) .. string.char(27) ..
                                         string.char(27))
end

function magicfind(target, secondary)
    remove_exclusions()

    if secondary then
        crawl.sendkeys(control('f') .. target .. "\r", arrowkey('d'), "\r\r" ..
            string.char(27) .. string.char(27) .. string.char(27))
    else
        magic(control('f') .. target .. "\r\r\r")
    end
end

function use_ability(name, extra, mute)
    for letter, abil in pairs(you.ability_table()) do
        if abil == name then
            if not mute then
                say("INVOKING " .. name .. ".")
            end
            magic("a" .. letter .. (extra or ""))
            return true
        end
    end
end

-- these few functions are called directly from ready()
function plan_message()
    if read_message then
        crawl.setopt("clear_messages = false")
        magic("_")
        read_message = false
    else
        crawl.setopt("clear_messages = true")
        magic(":qwqwqw\r")
        read_message = true
        have_message = false
        crawl.delay(2500)
    end
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

            if you.turns() ~= plan_turns[plan] or plan_result[plan] == nil then
                local result = plan()
                if not automatic then
                    return true
                end

                plan_turns[plan] = you.turns()
                plan_result[plan] = result

                if debug_channel("plans") then
                    dsay("Ran " .. plandata[2] .. ": " .. tostring(result))
                end

                if result == nil or result == true then
                    if DELAYED and result == true then
                        crawl.delay(next_delay)
                    end
                    next_delay = DELAY_TIME
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

                -- We haven't consumed a turn but might still need a planning
                -- update.
                if want_gameplan_update then
                    update_gameplan()
                end
            end
        end

        return false
    end
end

function initialize_plans()
    set_plan_emergency()
    set_plan_attack()
    set_plan_rest()
    set_plan_handle_acquirement_result()
    set_plan_pre_explore()
    set_plan_pre_explore2()
    set_plan_explore()
    set_plan_explore2()
    set_plan_stuck()
    set_plan_move()
end
