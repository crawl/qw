---------------------------------------------
-- ready function and main coroutine

function stop()
    qw.automatic = false
    unset_options()
end

function start()
    qw.automatic = true
    set_options()
    ready()
end

function startstop()
    if qw.automatic then
        stop()
    else
        start()
    end
end

function panic(msg)
    crawl.mpr("<lightred>" .. msg .. "</lightred>")
    stop()
end

function set_options()
    crawl.setopt("pickup_mode = multi")
    crawl.setopt("message_colour += mute:Search for what")
    crawl.setopt("message_colour += mute:Can't find anything")
    crawl.setopt("message_colour += mute:Drop what")
    crawl.setopt("message_colour += mute:Okay. then")
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
    crawl.setopt("message_colour -= mute:Okay. then")
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

function qw_main()
    turn_update()

    if qw.time_passed and qw.single_step then
        stop()
    end

    local did_restart = qw.restart_cascade
    if qw.automatic then
        crawl.flush_input()
        crawl.more_autoclear(true)
        if qw.have_message then
            plan_message()
        else
            plans.turn()
        end
    end
    -- restart_cascade must remain true for the entire move cascade while we're
    -- restarting.
    if did_restart then
        qw.restart_cascade = false
    end
end

function run_qw()
    if qw.abort then
        return
    end

    if qw.update_coroutine == nil then
        qw.update_coroutine = coroutine.create(qw_main)
    end

    local okay, err = coroutine.resume(qw.update_coroutine)
    if not okay then
        error("Error in coroutine: " .. err)
        qw.abort = true
    end

    if coroutine.status(qw.update_coroutine) == "dead" then
        qw.update_coroutine = nil
        qw.do_dummy_action = qw.do_dummy_action == nil and qw.restart_cascade
    else
        qw.do_dummy_action = qw.do_dummy_action == nil
    end

    local memory_count = collectgarbage("count")
    if debug_channel("throttle") and qw.throttle then
        dsay("Memory count is " .. tostring(memory_count))
    end

    if qw.max_memory and memory_count > qw.max_memory then
        collectgarbage("collect")

        if collectgarbage("count") > qw.max_memory then
            qw.abort = true
            dsay("Memory usage above " .. tostring(qw.max_memory))
            dsay("Aborting...")
            return
        end
    end
    qw.throttle = false

    if qw.do_dummy_action then
        crawl.process_keys(":" .. string.char(27) .. string.char(27))
    end
    qw.do_dummy_action = nil
end

function ready()
    run_qw()
end

function hit_closest()
    startstop()
end
