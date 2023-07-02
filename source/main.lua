---------------------------------------------
-- ready function and main coroutine

-- Max memory available to clua in megabytes. These defaults are overridden by
-- the MAX_MEMORY and MAX_MEMORY_PERCENTAGE rc variables, when those are
-- defined.
max_memory = 32
max_memory_percentage = 90

function stop()
    automatic = false
    unset_options()
end

function start()
    automatic = true
    set_options()
    ready()
end

function startstop()
    if automatic then
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

    if time_passed and SINGLE_STEP then
        stop()
    end

    local did_restart = restart_cascade
    if automatic then
        crawl.flush_input()
        crawl.more_autoclear(true)
        if have_message then
            plan_message()
        else
            plans.move()
        end
    end
    -- restart_cascade must remain true for the entire move cascade while we're
    -- restarting.
    if did_restart then
        restart_cascade = false
    end
end

function run_qw()
    if abort_qw then
        return
    end

    if update_coroutine == nil then
        update_coroutine = coroutine.create(qw_main)
    end

    local okay, err = coroutine.resume(update_coroutine)
    if not okay then
        error("Error in coroutine: " .. err)
        abort_qw = true
    end

    if coroutine.status(update_coroutine) == "dead" then
        update_coroutine = nil
        do_dummy_action = do_dummy_action == nil and restart_cascade
    else
        do_dummy_action = do_dummy_action == nil
    end

    local memory_count = collectgarbage("count")
    if debug_channel("throttle") and throttle then
        dsay("Memory count is " .. tostring(memory_count))
    end

    if memory_limit and memory_count > memory_limit then
        collectgarbage("collect")

        if collectgarbage("count") > memory_limit then
            abort_qw = true
            dsay("Memory usage above " .. tostring(memory_limit))
            dsay("Aborting...")
            return
        end
    end
    throttle = false

    if do_dummy_action then
        crawl.process_keys(":" .. string.char(27) .. string.char(27))
    end
    do_dummy_action = nil
end

function ready()
    run_qw()
end

function hit_closest()
    startstop()
end

function set_memory_limit(limit_mb)
    memory_limit = math.floor(limit_mb * 1024)
end
