------------------
-- Movement evaluation

function can_move_to(x, y)
    return is_traversable(x, y)
        and not view.withheld(x, y)
        and not monster_in_way(x, y)
end

function assess_square(x, y)
    a = {}

    -- Distance to current square
    a.supdist = supdist(x, y)

    -- Is current square near a BiA/SGD?
    if a.supdist == 0 then
        a.near_ally = count_bia(3) + count_greater_demons(3)
            + count_divine_warrior(3) > 0
    end

    -- Can we move there?
    a.can_move = a.supdist == 0
        or can_movenot view.withheld(x, y)
                      and not monster_in_way(x, y)
                      and is_traversable(x, y)
                      and not is_solid(x, y)
    if not a.can_move then
        return a
    end

    -- Count various classes of monsters from the enemy list.
    assess_square_monsters(a, x, y)

    -- Avoid corners if possible.
    a.cornerish = is_cornerish(x, y)

    -- Will we fumble if we try to attack from this square?
    a.fumble = not you.flying()
        and view.feature_at(x, y) == "shallow_water"
        and intrinsic_fumble()
        and not (you.god() == "Beogh" and you.piety_rank() >= 5)

    -- Will we be slow if we move into this square?
    a.slow = not you.flying()
        and view.feature_at(x, y) == "shallow_water"
        and not intrinsic_amphibious()
        and not intrinsic_flight()
        and not (you.god() == "Beogh" and you.piety_rank() >= 5)

    -- Is the square safe to step in? (checks traps & clouds)
    a.safe = view.is_safe_square(x, y)
    cloud = view.cloud_at(x, y)

    -- Would we want to move out of a cloud? note that we don't worry about
    -- weak clouds if monsters are around.
    a.cloud_safe = (cloud == nil)
        or a.safe
        or danger and not cloud_is_dangerous(cloud)

    -- Equal to 10000 if the move is not closer to any stair in good_stairs,
    -- otherwise equal to the (min) dist to such a stair
    a.stair_closer = stair_improvement(x, y)

    return a
end

-- returns a string explaining why moving a1->a2 is preferable to not moving
-- possibilities are:
--   cloud       - stepping out of harmful cloud
--   water       - stepping out of shallow water when it would cause fumbling
--   reaching    - kiting slower monsters with reaching
--   hiding      - moving out of sight of alert ranged enemies at distance >= 4
--   stealth     - moving out of sight of sleeping or wandering monsters
--   outnumbered - stepping away from a square adjacent to multiple monsters
--                 (when not cleaving)
--   fleeing     - moving towards stairs
function step_reason(a1, a2)
    if not (a2.can_move and a2.safe and a2.supdist > 0) then
        return false
    elseif (a2.fumble or a2.slow) and a1.cloud_safe then
        return false
    elseif not a1.near_ally
            and a2.stair_closer < 10000
            and a1.stair_closer > 0
            and a1.enemy_distance < 10
            -- Don't flee either from or to a place were we'll be opportunity
            -- attacked.
            and a1.adjacent == 0
            and a2.adjacent == 0
            and (reason_to_rest(90) or you.xl() <= 8 and disable_autoexplore)
            and not buffed()
            and (no_spells or starting_spell() ~= "Summon Small Mammal") then
        return "fleeing"
    elseif not a1.near_ally and a2.ranged == 0 and a2.adjacent == 0
            and a1.longranged > 0 then
        return "hiding"
    elseif not a1.near_ally and a2.ranged == 0 and a2.adjacent == 0
            and a2.unalert < a1.unalert then
        return "stealth"
    elseif not a1.cloud_safe then
        return "cloud"
    elseif a1.fumble then
        -- We require some close threats that try to say adjacent to us before
        -- we'll try to move out of water. We also require that we are no worse
        -- in at least one of ranged threats or enemy distance at the new
        -- position.
        if a1.followers_to_land
                and (a2.ranged <= a1.ranged
                    or a2.enemy_distance <= a1.enemy_distance) then
            return "water"
        else
            return false
        end
    elseif have_reaching() and a1.slow_adjacent > 0 and a2.adjacent == 0
                 and a2.ranged == 0 then
        return "reaching"
    elseif cleaving() then
        return false
    elseif a1.adjacent == 1 then
        return false
    elseif a2.adjacent + a2.ranged <= a1.adjacent + a1.ranged - 2 then
        return "outnumbered"
    else
        return false
    end
end

-- determines whether moving a0->a2 is an improvement over a0->a1
-- assumes that these two moves have already been determined to be better
-- than not moving, with given reasons
function step_improvement(bestreason, reason, a1, a2)
    if reason == "fleeing" and bestreason ~= "fleeing" then
        return true
    elseif bestreason == "fleeing" and reason ~= "fleeing" then
        return false
    elseif reason == "water" and bestreason == "water"
         and a2.enemy_distance < a1.enemy_distance then
        return true
    elseif reason == "water" and bestreason == "water"
         and a2.enemy_distance > a1.enemy_distance then
        return false
    elseif a2.adjacent + a2.ranged < a1.adjacent + a1.ranged then
        return true
    elseif a2.adjacent + a2.ranged > a1.adjacent + a1.ranged then
        return false
    elseif cleaving() and a2.ranged < a1.ranged then
        return true
    elseif cleaving() and a2.ranged > a1.ranged then
        return false
    elseif a2.adjacent + a2.ranged == 0 and a2.unalert < a1.unalert then
        return true
    elseif a2.adjacent + a2.ranged == 0 and a2.unalert > a1.unalert then
        return false
    elseif reason == "fleeing" and a2.stair_closer < a1.stair_closer then
        return true
    elseif reason == "fleeing" and a2.stair_closer > a1.stair_closer then
        return false
    elseif a2.enemy_distance < a1.enemy_distance then
        return true
    elseif a2.enemy_distance > a1.enemy_distance then
        return false
    elseif a2.stair_closer < a1.stair_closer then
        return true
    elseif a2.stair_closer > a2.stair_closer then
        return false
    elseif a1.cornerish and not a2.cornerish then
        return true
    else
        return false
    end
end

function choose_tactical_step()
    tactical_step = nil
    tactical_reason = "none"
    if you.confused()
            or you.berserk()
            or you.constricted()
            or not can_move()
            or in_branch("Slime")
            or you.status("spiked") then
        return
    end
    local a0 = assess_square(0, 0)
    if a0.cloud_safe
            and not (a0.fumble and sense_danger(3))
            and (not have_reaching() or a0.slow_adjacent == 0)
            and (a0.adjacent <= 1 or cleaving())
            and (a0.near_ally or a0.enemy_distance == 10) then
        return
    end
    local bestx, besty, bestreason
    local besta = nil
    local x, y
    local a
    local reason
    for x, y in adjacent_iter(0, 0) do
        a = assess_square(x, y)
        reason = step_reason(a0, a)
        if reason then
            if besta == nil
                    or step_improvement(bestreason, reason, besta, a) then
                bestx = x
                besty = y
                besta = a
                bestreason = reason
            end
        end
    end
    if besta then
        tactical_step = delta_to_vi(bestx, besty)
        tactical_reason = bestreason
    end
end
