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
    if prompt:find("next level anyway") then
        return true
    end
    if prompt:find("fire in the non-hostile")
            or prompt:find("fire at your") then
        return true
    end
    if prompt:find("Really.*into that.*trap")
            or prompt:find("into the Zot trap") then
        return true
    end
    if prompt:find("Really explore while Zot is near") then
        return true
    end
end

function control(c)
    return string.char(string.byte(c) - string.byte('a') + 1)
end

local a2c = { ['u'] = -254, ['d'] = -253, ['l'] = -252 ,['r'] = -251 }
function arrowkey(c)
    return a2c[c]
end

local d2v = {
    [-1] = { [-1] = 'y', [0] = 'h', [1] = 'b' },
    [0]  = { [-1] = 'k', [1] = 'j' },
    [1]  = { [-1] = 'u', [0] = 'l', [1] = 'n' },
}
local v2d = {}
for x, _ in pairs(d2v) do
    for y, c in pairs(d2v[x]) do
        v2d[c] = { x = x, y = y }
    end
end

function delta_to_vi(pos)
    return d2v[pos.x][pos.y]
end

function vi_to_delta(c)
    return v2d[c]
end

function vector_move(pos)
    local str = ''
    for i = 1, abs(pos.x) do
        str = str .. delta_to_vi({ x = sign(pos.x), y = 0 })
    end
    for i = 1, abs(pos.y) do
        str = str .. delta_to_vi({ x = 0, y = sign(pos.y) })
    end
    return str
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
    if text:find("Your surroundings suddenly seem different") then
        invis_monster = false
    elseif text:find("Your pager goes off") then
        have_message = true
    elseif text:find("Done exploring") then
        c_persist.autoexplore[you.where()] = const.autoexplore.full
        want_goal_update = true
    elseif text:find("Partly explored") then
        if text:find("transporter") then
            c_persist.autoexplore[you.where()] = const.autoexplore.transporter
        else
            c_persist.autoexplore[you.where()] = const.autoexplore.partial
        end
        want_goal_update = true
    elseif text:find("Could not explore") then
        c_persist.autoexplore[you.where()] = const.autoexplore.runed_door
        want_goal_update = true
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
                update_stone_stairs(branch, depth, dir, num,
                    { feat = const.feat_state.explored })
                update_stone_stairs(branch, depth + dir, travel_dir,
                    travel_num, { feat = const.feat_state.explored })
            end
        end
        stairs_travel = nil
    elseif text:find("You pick up the.*rune and feel its power") then
        want_goal_update = true
    elseif text:find("abyssal rune vanishes from your memory and reappears")
            or text:find("detect the abyssal rune") then
        c_persist.sensed_abyssal_rune = true
    -- Timed portals are recorded by the "Hurry and find it" message handling,
    -- but a permanent bazaar doesn't have this. Check messages for "a gateway
    -- to a bazaar", which happens via autoexplore. Timed bazaars are described
    -- as "a flickering gateway to a bazaar", so by looking for the right
    -- message, we prevent counting timed bazaars twice.
    elseif text:find("abyssal rune vanishes from your memory") then
        c_persist.sensed_abyssal_rune = false
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
                    if turns ~= const.inf_turns then
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
    elseif text:find("You feel very bouyant") then
        temporary_flight = true
    elseif text:find("You pick up the Orb of Zot") then
        want_goal_update = true
    elseif text:find("You die...") then
        crawl.sendkeys(string.char(27) .. string.char(27)
            .. string.char(27))
    end
end
