----------------------
-- Tactical steps

function assess_square_enemies(a)
    local move_delay = player_move_delay()
    local best_dist = 10
    a.enemy_distance = 0
    a.followers = false
    a.adjacent = 0
    a.kite_adjacent = 0
    a.ranged = 0
    a.unalert = 0
    a.longranged = 0
    for _, enemy in ipairs(qw.enemy_list) do
        local dist = enemy:melee_move_distance(a.pos)
        local see_cell = cell_see_cell(a.pos, enemy:pos())
        local ranged = enemy:is_ranged()
        local liquid_bound = enemy:is_liquid_bound()

        if dist < best_dist then
            best_dist = dist
        end

        if dist == 1 then
            a.adjacent = a.adjacent + 1

            if not liquid_bound and not ranged then
                a.followers = true
            end

            if (player_reach_range() > 1 or using_ranged_weapon())
                    and not ranged
                    and move_delay < enemy:move_delay() then
                a.kite_adjacent = a.kite_adjacent + 1
            end
        end

        if dist > 1
                and see_cell
                and enemy:has_path_to_player()
                and (ranged
                    or dist == 2
                        and enemy:move_delay() < move_delay) then
            a.ranged = a.ranged + 1
        end

        if dist > 1 and see_cell and enemy:is_unalert() then
            a.unalert = a.unalert + 1
        end

        if dist >= 4
                and see_cell
                and ranged
                and enemy:has_path_to_player() then
            a.longranged = a.longranged + 1
        end
    end

    a.enemy_distance = best_dist
end

function assess_square(pos)
    a = { pos = pos }

    -- Distance to current square
    a.supdist = supdist(pos)

    -- Is current square near an ally?
    if a.supdist == 0 then
        a.near_ally = check_allies(3)
    end

    -- Can we move there?
    a.can_move = a.supdist == 0 or can_move_to(pos, const.origin)
    if not a.can_move then
        return a
    end

    local in_water = view.feature_at(pos.x, pos.y) == "shallow_water"
        and not (you.flying()
            or you.god() == "Beogh" and you.piety_rank() >= 5)
    a.sticky_fire_danger = 0
    if not in_water and you.status("on fire") and you.res_fire() < 2 then
        a.sticky_fire_danger = 2 - a.supdist
    end

    -- Avoid corners if possible.
    a.cornerish = is_cornerish_at(pos)

    -- Is the wall next to us dangerous?
    a.bad_walls = count_adjacent_slimy_walls_at(pos)

    -- Will we fumble if we try to attack from this square?
    a.fumble = not using_ranged_weapon() and in_water and intrinsic_fumble()

    -- Will we be slow if we move into this square?
    a.slow = in_water and not intrinsic_amphibious()

    -- Is the square safe to step in? (checks traps & clouds)
    a.safe = is_safe_at(pos)

    -- Would we want to move out of a cloud? We don't worry about weak clouds
    -- if monsters are around.
    a.cloud_dangerous = cloud_is_dangerous_at(pos)

    a.retreat_distance = retreat_distance_at(pos)

    -- Count various classes of monsters from the enemy list.
    assess_square_enemies(a, pos)

    return a
end

-- returns a string explaining why moving a1->a2 is preferable to not moving
-- possibilities are:
--   sticky fire - moving to put out sticky fire
--   cloud       - stepping out of harmful cloud
--   wall        - stepping away from a slimy wall
--   water       - stepping out of shallow water when it would cause fumbling
--   kiting      - kiting slower monsters with a reaching or ranged weapon
--   retreating  - retreating to a better defensive position
--   hiding      - moving out of sight of alert ranged enemies at distance >= 4
--   stealth     - moving out of sight of sleeping or wandering monsters
--   outnumbered - stepping away from adjacent and/or ranged monsters
function step_reason(a1, a2)
    local bad_form = in_bad_form()
    if not (a2.can_move and a2.safe and a2.supdist > 0) then
        return
    elseif a2.sticky_fire_danger < a1.sticky_fire_danger then
        return "sticky fire"
    elseif (a2.fumble or a2.slow or a2.bad_walls > 0) and not a1.cloud_dangerous then
        return
    -- We've already required that a2 is safe.
    elseif a1.cloud_dangerous then
        return "cloud"
    elseif a1.fumble then
        -- We require that we have some close threats we want to melee that
        -- try to stay adjacent to us before we'll try to move out of water.
        -- We also require that we are no worse in at least one of ranged
        -- threats or enemy distance at the new position.
        if (not get_ranged_target() and a1.followers)
                and (a2.ranged <= a1.ranged
                    or a2.enemy_distance <= a1.enemy_distance) then
            return "water"
        else
            return
        end
    elseif a1.bad_walls > 0 then
        -- We move away from bad walls if we're using an attack affected by
        -- the walls. We also use the same additional consideration or ranged
        -- threat and distance as used for water.
        local target = get_ranged_target()
        if (not (target and target.attack.type == const.attack.evoke)
                and a1.followers)
                and (a2.ranged <= a1.ranged
                    or a2.enemy_distance <= a1.enemy_distance) then
            return "wall"
        else
            return
        end
    elseif a1.kite_adjacent > 0 and a2.adjacent == 0 and a2.ranged == 0 then
        return "kiting"
    elseif a2.retreat_distance < a1.retreat_distance then
        return "retreating"
    elseif a1.retreat_distance == 0 then
        return
    elseif not using_ranged_weapon()
            and not want_to_move_to_abyss_objective()
            and not a1.near_ally
            and a2.ranged == 0
            and a2.adjacent == 0
            and a1.longranged > 0 then
        return "hiding"
    elseif not using_ranged_weapon()
            and not want_to_move_to_abyss_objective()
            and not a1.near_ally
            and a2.ranged == 0
            and a2.adjacent == 0
            and a2.unalert < a1.unalert then
        return "stealth"
    elseif not using_cleave()
            and a1.adjacent > 1
            and a2.adjacent + a2.ranged <= a1.adjacent + a1.ranged - 2
            -- We also need to be sure that any monsters we're stepping away
            -- from can eventually reach us, otherwise we'll be stuck in a loop
            -- constantly stepping away and then towards them.
            and qw.incoming_monsters_turn == you.turns() then
        return "outnumbered"
    end
end

-- Determines whether moving a0->a2 is an improvement over a0->a1 assumes that
-- these two moves have already been determined to be better than not moving,
-- with given reasons
function step_improvement(best_reason, reason, a1, a2)
    if reason == "sticky fire"
            and (best_reason ~= "sticky fire"
                or a2.sticky_fire_danger < a1.sticky_fire_danger) then
        return true
    elseif best_reason == "sticky fire"
            and (reason ~= "sticky fire"
                or a2.sticky_fire_danger > a1.sticky_fire_danger) then
        return false
    elseif reason == "cloud" and best_reason ~= "cloud" then
        return true
    elseif best_reason == "cloud" and reason ~= "cloud" then
        return false
    elseif reason == "wall"
            and (best_reason ~= "wall"
                or a2.bad_walls < a1.bad_walls) then
        return true
    elseif best_reason == "wall"
            and (reason ~= "wall"
                or a2.bad_walls > a1.bad_walls) then
        return false
    elseif reason == "water" and best_reason ~= "water" then
        return true
    elseif best_reason == "water" and reason ~= "water" then
        return false
    elseif reason == "retreating"
            and (best_reason ~= "retreating"
                or a2.retreat_distance < a1.retreat_distance
                or a2.retreat_distance == a1.retreat_distance
                    and a2.enemy_distance > a1.enemy_distance) then
        return true
    elseif best_reason == "retreating"
            and (reason ~= "retreating"
                or a2.retreat_distance > a1.retreat_distance
                or a2.retreat_distance == a1.retreat_distance
                    and a2.enemy_distance < a1.enemy_distance) then
        return false
    elseif a2.adjacent + a2.ranged < a1.adjacent + a1.ranged then
        return true
    elseif a2.adjacent + a2.ranged > a1.adjacent + a1.ranged then
        return false
    elseif want_to_be_surrounded() and a2.ranged < a1.ranged then
        return true
    elseif want_to_be_surrounded() and a2.ranged > a1.ranged then
        return false
    elseif a2.adjacent + a2.ranged == 0 and a2.unalert < a1.unalert then
        return true
    elseif a2.adjacent + a2.ranged == 0 and a2.unalert > a1.unalert then
        return false
    elseif a2.enemy_distance < a1.enemy_distance then
        return true
    elseif a2.enemy_distance > a1.enemy_distance then
        return false
    elseif a1.cornerish and not a2.cornerish then
        return true
    else
        return false
    end
end

function choose_tactical_step()
    qw.tactical_step = nil
    qw.tactical_reason = nil

    if unable_to_move()
            or dangerous_to_move()
            -- For cloud and sticky fire steps, we'd like to be able to try
            -- these even while confused, so long as we're not also dealing
            -- with monsters.
            or you.confused() and qw.danger_in_los
            or you.berserk() and qw.danger_in_los
            or you.constricted() then
        if debug_channel("move") then
            dsay("No tactical step chosen: not safe to take step")
        end

        return
    end

    local a0 = assess_square(const.origin)
    local danger = check_enemies(3)
    if not a0.cloud_dangerous
            and a0.sticky_fire_danger == 0
            and not (a0.fumble and danger)
            and not (a0.bad_walls > 0 and danger)
            and a0.kite_adjacent == 0
            and a0.retreat_distance == 0
            and (a0.near_ally or a0.enemy_distance == const.inf_dist) then
        if debug_channel("move") then
            dsay("No tactical step chosen: current position is good enough")
        end

        return
    end

    local best_pos, best_reason, besta
    for pos in adjacent_iter(const.origin) do
        local a = assess_square(pos)
        local reason = step_reason(a0, a)
        if reason then
            if besta == nil
                    or step_improvement(best_reason, reason, besta, a) then
                best_pos = pos
                besta = a
                best_reason = reason
            end
        end
    end
    if besta then
        qw.tactical_step = best_pos
        qw.tactical_reason = best_reason

        if debug_channel("move") then
            dsay("Chose tactical step to "
                .. cell_string_from_position(qw.tactical_step)
                .. " for reason: " .. qw.tactical_reason)
        end

        return
    end

    if debug_channel("move") then
        dsay("No tactical step chosen: no valid step found")
    end
end
