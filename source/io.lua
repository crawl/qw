-------------------
-- Some general input and message output handling, as well as in-game message
-- parsing.

function note(x)
    crawl.take_note(you.turns() .. " ||| " .. x)
end

function say(x)
    crawl.mpr(you.turns() .. " ||| " .. x)
    note(x)
end

function c_answer_prompt(prompt)
    if prompt == "Die?" then
        return WIZMODE_DEATH
    end
    if prompt:find("Have to go through") then
        return true
    end
    if prompt:find("transient mutations") then
        return true
    end
    if prompt:find("Keep disrobing") then
        return false
    end
    if prompt:find("Really unwield") or prompt:find("Really take off")
         or prompt:find("Really remove") or prompt:find("Really wield")
         or prompt:find("Really wear") or prompt:find("Really put on")
         or prompt:find("Really quaff") then
        return true
    end
    if prompt:find("Keep reading") then
        return true
    end
    if prompt:find("This attack would place you under penance") then
        return false
    end
    if prompt:find("You cannot afford")
            and prompt:find("travel there anyways") then
        return true
    end
    if prompt:find("Shopping list") then
        return false
    end
    if prompt:find("Are you sure you want to drop") then
        return true
    end
    if prompt:find("Really rampage") then
        return true
    end
    if prompt:find("Really drink that potion of mutation") then
        return true
    end
end

function ch_stash_search_annotate_item(it)
    return ""
end

-- A hook for incoming game messages. Note that this is executed for every new
-- message regardless of whether turn_update() this turn (e.g during
-- autoexplore or travel)). Hence this function shouldn't depend on any state
-- variables managed by turn_update(). Use the clua interfaces like you.where()
-- directly to get info about game status.
function c_message(text, channel)
    if text:find("Sigmund flickers and vanishes") and you.xl() < 10 then
        invis_caster = true
    elseif text:find("Your surroundings suddenly seem different") then
        invis_caster = false
    elseif text:find("Your pager goes off") then
        have_message = true
    elseif text:find("Done exploring") then
        c_persist.autoexplore[you.where()] = AUTOEXP.FULL
        want_gameplan_update = true
    elseif text:find("Partly explored") then
        if text:find("transporter") then
            c_persist.autoexplore[you.where()] = AUTOEXP.TRANSPORTER
        else
            c_persist.autoexplore[you.where()] = AUTOEXP.PARTIAL
        end
        want_gameplan_update = true
    elseif text:find("Could not explore") then
        c_persist.autoexplore[you.where()] = AUTOEXP.RUNED_DOOR
        want_gameplan_update = true
    -- Track which stairs we've fully explored by watching pairs of messages
    -- corresponding to standing on stairs and then taking them. The climbing
    -- message happens before the level transition.
    elseif text:find("You climb downwards")
            or text:find("You fly downwards")
            or text:find("You climb upwards")
            or text:find("You fly upwards") then
        stairs_travel = view.feature_at(0, 0)
    -- Record the staircase if we had just set stairs_travel.
    elseif text:find("There is a stone staircase") then
        if stairs_travel then
            local feat = view.feature_at(0, 0)
            local dir, num = stone_stairs_type(feat)
            local travel_dir, travel_num = stone_stairs_type(stairs_travel)
            -- Sanity check to make sure the stairs correspond.
            if travel_dir and dir and travel_dir == -dir
                    and travel_num == num then
                local branch, depth = parse_level_range(you.where())
                update_stairs(branch, depth, feat, { los = FEAT_LOS.EXPLORED })
                update_stairs(branch, depth + dir, stairs_travel,
                    { los = FEAT_LOS.EXPLORED })
            end
        end
        stairs_travel = nil
    elseif text:find("Orb of Zot") then
        c_persist.found_orb = true
        want_gameplan_update = true
    -- Timed portals are recorded by the "Hurry and find it" message handling,
    -- but a permanent bazaar doesn't have this. Check messages for "a gateway
    -- to a bazaar", which happens via autoexplore. Timed bazaars are described
    -- as "a flickering gateway to a bazaar", so by looking for the right
    -- message, we prevent counting timed bazaars twice.
    elseif text:find("Found a gateway to a bazaar") then
        record_portal(you.where(), "Bazaar", true)
    elseif text:find("Hurry and find it")
            or text:find("Find the entrance") then
        for portal, _ in pairs(portal_data) do
            if text:lower():find(portal_description(portal):lower()) then
                record_portal(you.where(), portal)
                break
            end
        end
    elseif text:find("The walls and floor vibrate strangely") then
        local where = you.where()
        -- If there was only one timed portal on the level, we can be sure it's
        -- the one that expired.
        if c_persist.portals[where] then
            local count = 0
            local expired_portal
            for portal, turns_list in pairs(c_persist.portals[where]) do
                for _, turns in ipairs(turns_list) do
                    if turns ~= INF_TURNS then
                        count = count + 1
                        if count > 1 then
                            expired_portal = nil
                            break
                        end

                        expired_portal = portal
                    end
                end
            end
            if expired_portal then
                remove_portal(where, expired_portal)
            end
        end
    elseif text:find("You enter the transporter") then
        transp_zone = transp_zone + 1
        transp_orient = true
    elseif text:find("You enter a dispersal trap")
            or text:find("You enter a permanent teleport trap") then
        ignore_traps = false
    end
end
