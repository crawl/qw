---------------------------------------------
-- ready function and main coroutine

-- Max memory available to clua in kilobytes
MAX_MEMORY = 16000

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

function qw_main()
    turn_update()

    if time_passed and SINGLE_STEP then
        stop()
    end

    if automatic then
        crawl.flush_input()
        crawl.more_autoclear(true)
        if have_message then
            plan_message()
        else
            plan_move()
        end
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
        do_dummy_action = false
    else
        do_dummy_action = true
    end

    if collectgarbage("count") > memory_limit then
        collectgarbage("collect")

        if collectgarbage("count") > memory_limit then
            abort_qw = true
            dsay("Memory usage above " .. tostring(memory_limit))
            dsay("Aborting...")
            return
        end
    end

    if do_dummy_action then
        crawl.process_keys(":" .. string.char(27) .. string.char(27))
    end
end

function ready()
    run_qw()
end

function hit_closest()
    startstop()
end

function resume_qw()
    abort_qw = false
end

function set_memory_limit(limit)
    memory_limit = limit
end
