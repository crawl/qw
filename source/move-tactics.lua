----------------------
-- Tactical steps

function assess_square_enemies(a, pos)
    local best_dist = 10
    a.enemy_distance = 0
    a.followers = false
    a.adjacent = 0
    a.kite_adjacent = 0
    a.ranged = 0
    a.unalert = 0
    a.longranged = 0
    for _, enemy in ipairs(qw.enemy_list) do
        local dist = enemy:distance()
        local see_cell = cell_see_cell(pos, enemy:pos())
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

            if (have_reaching() or have_ranged_weapon())
                    and not ranged
                    and enemy:speed() < player_speed() then
                a.kite_adjacent = a.kite_adjacent + 1
            end
        end

        if dist > 1
                and see_cell
                and (ranged or dist == 2 and enemy:is_fast()) then
            a.ranged = a.ranged + 1
        end

        if dist > 1
                and see_cell
                and (enemy:is("wandering")
                    or enemy:is("sleeping")
                    or enemy:is("dormant")) then
            a.unalert = a.unalert + 1
        end

        if dist >= 4
                and see_cell
                and ranged
                and not (enemy:is("wandering")
                    or enemy:is("sleeping")
                    or enemy:is("dormant")
                    or enemy:is("dumb")
                    or liquid_bound
                    or enemy:is_stationary())
                and enemy:has_path_to_player() then
            a.longranged = a.longranged + 1
        end
    end

    a.enemy_distance = best_dist
end

function assess_square(pos)
    a = {}

    -- Distance to current square
    a.supdist = supdist(pos)

    -- Is current square near an ally?
    if a.supdist == 0 then
        a.near_ally = check_allies(3)
    end

    -- Can we move there?
    a.can_move = a.supdist == 0 or can_move_to(pos)
    if not a.can_move then
        return a
    end

    -- Count various classes of monsters from the enemy list.
    assess_square_enemies(a, pos)

    -- Avoid corners if possible.
    a.cornerish = is_cornerish_at(pos)

    -- Will we fumble if we try to attack from this square?
    a.fumble = not you.flying()
        and view.feature_at(pos.x, pos.y) == "shallow_water"
        and intrinsic_fumble()
        and not (you.god() == "Beogh" and you.piety_rank() >= 5)

    -- Is the wall next to us dangerous?
    a.bad_wall = count_adjacent_slimy_walls_at(pos) > 0

    -- Will we be slow if we move into this square?
    a.slow = not you.flying()
        and view.feature_at(pos.x, pos.y) == "shallow_water"
        and not intrinsic_amphibious()
        and not (you.god() == "Beogh" and you.piety_rank() >= 5)

    -- Is the square safe to step in? (checks traps & clouds)
    a.safe = is_safe_at(pos)

    -- Would we want to move out of a cloud? note that we don't worry about
    -- weak clouds if monsters are around.
    a.cloud_safe = is_cloud_safe_at(pos, a.safe)

    return a
end

-- returns a string explaining why moving a1->a2 is preferable to not moving
-- possibilities are:
--   cloud       - stepping out of harmful cloud
--   water       - stepping out of shallow water when it would cause fumbling
--   kiting      - kiting slower monsters with reaching or a ranged weapon
--   hiding      - moving out of sight of alert ranged enemies at distance >= 4
--   stealth     - moving out of sight of sleeping or wandering monsters
--   outnumbered - stepping away from a square adjacent to multiple monsters
--                 (when not cleaving)
function step_reason(a1, a2)
    local bad_form = in_bad_form()
    if not (a2.can_move and a2.safe and a2.supdist > 0) then
        return false
    elseif (a2.fumble or a2.slow or a2.bad_wall) and a1.cloud_safe then
        return false
    elseif not have_ranged_weapon()
            and not want_to_move_to_abyss_objective()
            and not a1.near_ally
            and a2.ranged == 0
            and a2.adjacent == 0
            and a1.longranged > 0 then
        return "hiding"
    elseif not have_ranged_weapon()
            and not want_to_move_to_abyss_objective()
            and not a1.near_ally
            and a2.ranged == 0
            and a2.adjacent == 0
            and a2.unalert < a1.unalert then
        return "stealth"
    elseif not a1.cloud_safe then
        return "cloud"
    elseif a1.fumble then
        -- We require that we have some close threats we want to melee that try
        -- to stay adjacent to us before we'll try to move out of water. We
        -- also require that we are no worse in at least one of ranged threats
        -- or enemy distance at the new position.
        if (not have_ranged_target() and a1.followers)
                and (a2.ranged <= a1.ranged
                    or a2.enemy_distance <= a1.enemy_distance) then
            return "water"
        else
            return false
        end
    elseif a1.bad_wall then
        -- Same conditions for dangerous walls as for water.
        if (have_ranged_target() or a1.followers)
                and (a2.ranged <= a1.ranged
                    or a2.enemy_distance <= a1.enemy_distance) then
            return "wall"
        else
            return false
        end
    elseif a1.kite_adjacent > 0 and a2.adjacent == 0 and a2.ranged == 0 then
        return "kiting"
    elseif want_to_be_surrounded() then
        return false
    elseif a1.adjacent == 1 then
        return false
    elseif a2.adjacent + a2.ranged <= a1.adjacent + a1.ranged - 2
            -- We also need to be sure that any monsters we're stepping away
            -- from can eventually reach us, otherwise we'll be stuck in a loop
            -- constantly stepping away and then towards them.
            and incoming_melee_turn == you.turns() then
        return "outnumbered"
    else
        return false
    end
end

-- determines whether moving a0->a2 is an improvement over a0->a1
-- assumes that these two moves have already been determined to be better
-- than not moving, with given reasons
function step_improvement(best_reason, reason, a1, a2)
    if reason == "water" and best_reason == "water"
         and a2.enemy_distance < a1.enemy_distance then
        return true
    elseif reason == "water" and best_reason == "water"
         and a2.enemy_distance > a1.enemy_distance then
        return false
    elseif reason == "wall" and best_reason == "wall"
         and a2.enemy_distance < a1.enemy_distance then
        return true
    elseif reason == "wall" and best_reason == "wall"
         and a2.enemy_distance > a1.enemy_distance then
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
            or you.confused()
            or you.berserk()
            or you.constricted() then
        return
    end

    local a0 = assess_square(const.origin)
    local danger = check_enemies(3)
    if a0.cloud_safe
            and not (a0.fumble and danger)
            and not (a0.bad_wall and danger)
            and a0.kite_adjacent == 0
            and (a0.near_ally or a0.enemy_distance == 10) then
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
    end
end
