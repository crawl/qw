----------------------
-- Tactical steps

function assess_square_enemies(a)
    local move_delay = player_move_delay()
    local best_dist = const.inf_dist
    a.followers = false
    a.melee_count = 0
    a.ranged = 0
    a.unalert = 0
    a.longranged = 0
    for _, enemy in ipairs(qw.enemy_list) do
        local dist = enemy:melee_move_distance(a.pos)
        local see_cell = cell_see_cell(enemy:pos(), a.pos)
        local ranged = enemy:is_ranged(true)
        local liquid_bound = enemy:is_liquid_bound()

        if dist < best_dist then
            best_dist = dist
        end

        if dist == 0 then
            a.melee_count = a.melee_count + 1
        end

        if dist > 0
                and see_cell
                and (ranged
                    or dist == 1
                        and enemy:has_path_to_melee_player()
                        and enemy:move_delay() < move_delay) then
            a.ranged = a.ranged + 1
        end

        if dist > 0 and see_cell and enemy:is_unalert() then
            a.unalert = a.unalert + 1
        end

        if dist >= 3
                and see_cell
                and ranged
                and enemy:has_path_to_melee_player() then
            a.longranged = a.longranged + 1
        end
    end

    a.enemy_move_dist = best_dist
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

    -- Is the square safe to step in? (checks traps & clouds)
    a.safe = is_safe_at(pos)

    -- Would we want to move out of a cloud? We don't worry about weak clouds
    -- if monsters are around.
    a.cloud_dangerous = cloud_is_dangerous_at(pos)

    a.dangerous_tree_count = qw.awaken_forest and count_trees_at(pos) or 0

    a.retreat_dist = retreat_distance_at(pos)

    a.kite = is_kite_step(a.pos)

    local in_water = in_water_at(pos)
    a.sticky_fire_danger = 0
    if not in_water and you.status("on fire") and you.res_fire() < 2 then
        a.sticky_fire_danger = 2 - a.supdist
    end

    a.frost_wall = qw.creeping_frost_count > 0
        and is_adjacent_solid_wall_at(pos)

    a.slimy_wall_count = count_slimy_walls_at(pos)

    -- Will we fumble if we try to attack from this square?
    a.fumble = not using_ranged_weapon() and in_water and intrinsic_fumble()

    -- Will we be slow if we move into this square?
    a.slow = in_water and not intrinsic_amphibious()

    -- Count various classes of monsters from the enemy list.
    assess_square_enemies(a, pos)

    -- Avoid corners if possible.
    a.cornerish = is_cornerish_at(pos)

    return a
end

-- returns a string explaining why moving a1->a2 is preferable to not moving
-- possibilities are:
--   sticky fire    - moving to put out sticky fire
--   cloud          - stepping out of harmful cloud
--   kiting         - kiting slower monsters with a reaching or ranged weapon
--   retreating     - retreating to a better defensive position
function step_reason(a1, a2)
    -- If we step away from dangerous things that don't go away fairly quickly
    -- (or at all), we want to be guaranteed to have a monster follow us so
    -- that we can attack directly at the new position.
    local can_step_away = qw.incoming_monsters
        and (a1.melee_count > 0 or best_ranged_target())
    if not (a2.can_move and a2.safe and a2.supdist > 0) then
        return
    elseif a2.sticky_fire_danger < a1.sticky_fire_danger then
        return "sticky fire"
    -- We've already required that a2 is safe.
    elseif a1.cloud_dangerous then
        return "cloud"
    elseif a2.kite then
        return "kiting"
    -- If we're either not kiting or we wanted to kite step but couldn't, it's
    -- ok to retreat. We don't want to retreat if we should be doing a kiting
    -- attack.
    elseif (not want_to_kite() or want_to_kite_step())
            and a2.retreat_dist < a1.retreat_dist then
        return "retreating"
    end
end

local step_keys = { "sticky_fire_danger", "cloud_dangerous",
    "dangerous_tree_count", "kite", "retreat_dist", "fumble", "frost_wall",
    "slimy_wall_count", "slow", "near_ally", "adjacent", "ranged", "unalert",
    "enemy_move_dist", "cornerish" }
local rev_step_keys = { "sticky_fire_danger", "cloud_dangerous",
    "dangerous_tree_count", "retreat_dist", "fumble", "frost_wall",
    "slimy_wall_count", "slow", "near_ally", "adjacent", "ranged", "unalert",
    "cornerish" }
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
    if a0.sticky_fire_danger == 0
            and not a0.cloud_dangerous
            and not want_to_kite()
            and a0.retreat_dist == 0 then
        if debug_channel("move") then
            dsay("No tactical step chosen: current position is good enough")
        end

        return
    end

    local best_pos, best_reason, besta
    for pos in adjacent_iter(const.origin) do
        local a = assess_square(pos)
        local reason = step_reason(a0, a)
        -- If reason is defined, we have sufficient reason to move from a0->a.
        if reason and (not besta
                or compare_table_keys(a, besta, step_keys, rev_step_keys)) then
            best_pos = pos
            besta = a
            best_reason = reason
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
