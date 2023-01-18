------------------
-- Movement evaluation

function can_move_to(pos)
    return is_traversable(pos)
        and not view.withheld(pos.x, pos.y)
        and not monster_in_way(pos)
end

function tabbable_square(pos)
    if view.feature_at(pos.x, pos.y) ~= "unseen"
            and view.is_safe_square(pos.x, pos.y) then
        if not monster_array[pos.x][pos.y]
                or not monster_array[pos.x][pos.y]:is_firewood() then
            return true
        end
    end
    return false
end

-- Should only be called for adjacent squares.
function monster_in_way(pos)
    local mons = monster_array[pos.x][pos.y]
    local feat = view.feature_at(0, 0)
    return mons and (mons:attitude() <= enum_att_neutral
            and not branch_step_mode
        or mons:attitude() > enum_att_neutral
            and (mons:is_constricted()
                or mons:is_caught()
                or mons:status("petrified")
                or mons:status("paralysed")
                or mons:status("constricted by roots")
                or mons:is("sleeping")
                or not mons:can_traverse(0, 0)
                or feat  == "trap_zot"))
end

function assess_square_enemies(a, cx, cy)
    local best_dist = 10
    a.enemy_distance = 0
    a.followers_to_land = false
    a.adjacent = 0
    a.slow_adjacent = 0
    a.ranged = 0
    a.unalert = 0
    a.longranged = 0
    for _, enemy in ipairs(enemy_list) do
        local pos = enemy:pos()
        local dist = enemy:distance()
        local see_cell = view.cell_see_cell(cx, cy, pos.x, pos.y)
        local ranged = enemy:is_ranged()
        local liquid_bound = enemy:is_liquid_bound()

        if dist < best_dist then
            best_dist = dist
        end

        if dist == 1 then
            a.adjacent = a.adjacent + 1

            if not liquid_bound
                    and not ranged
                    and enemy:reach_range() < 2 then
                a.followers_to_land = true
            end

            if have_reaching()
                    and not ranged
                    and enemy:reach_range() < 2
                    and enemy:speed() < player_speed() then
                a.slow_adjacent = a.slow_adjacent + 1
            end
        end

        if dist > 1
                and see_cell
                and (dist == 2
                        and (enemy:is_fast() or enemy:reach_range() >= 2)
                    or ranged) then
            a.ranged = a.ranged + 1
        end

        if dist > 1
                and see_cell
                and (enemy:desc():find("wandering")
                        and not enemy:desc():find("mushroom")
                    or enemy:desc():find("sleeping")
                    or enemy:desc():find("dormant")) then
            a.unalert = a.unalert + 1
        end

        if dist >= 4
                and see_cell
                and ranged
                and not (enemy:desc():find("wandering")
                    or enemy:desc():find("sleeping")
                    or enemy:desc():find("dormant")
                    or enemy:desc():find("stupefied")
                    or liquid_bound
                    or enemy:is_stationary())
                and enemy:can_move_to_melee_player() then
            a.longranged = a.longranged + 1
        end

    end

    a.enemy_distance = best_dist
end

function distance_to_enemy()
    local best_dist = 10
    for _, enemy in ipairs(enemy_list) do
        if enemy:distance() < best_dist then
            best_dist = enemy:distance()
        end
    end
    return best_dist
end

function distance_to_tabbable_enemy()
    local best_dist = 10
    for _, enemy in ipairs(enemy_list) do
        if enemy:distance() < best_dist
                and enemy:can_move_to_melee_player() then
            best_dist = enemy:distance()
        end
    end
    return best_dist
end
function assess_square(pos)
    a = {}

    -- Distance to current square
    a.supdist = supdist(pos.x, pos.y)

    -- Is current square near a BiA/SGD?
    if a.supdist == 0 then
        a.near_ally = count_bia(3) + count_greater_demons(3)
            + count_divine_warrior(3) > 0
    end

    -- Can we move there?
    a.can_move = a.supdist == 0
        or can_movenot view.withheld(pos.x, pos.y)
                      and not monster_in_way(pos)
                      and is_traversable_at(pos)
                      and not is_solid_at(pos)
    if not a.can_move then
        return a
    end

    -- Count various classes of monsters from the enemy list.
    assess_square_monsters(a, pos)

    -- Avoid corners if possible.
    a.cornerish = is_cornerish_at(pos)

    -- Will we fumble if we try to attack from this square?
    a.fumble = not you.flying()
        and view.feature_at(pos.x, pos.y) == "shallow_water"
        and intrinsic_fumble()
        and not (you.god() == "Beogh" and you.piety_rank() >= 5)

    -- Will we be slow if we move into this square?
    a.slow = not you.flying()
        and view.feature_at(pos.x, pos.y) == "shallow_water"
        and not intrinsic_amphibious()
        and not intrinsic_flight()
        and not (you.god() == "Beogh" and you.piety_rank() >= 5)

    -- Is the square safe to step in? (checks traps & clouds)
    a.safe = view.is_safe_square(pos.x, pos.y)
    cloud = view.cloud_at(pos.x, pos.y)

    -- Would we want to move out of a cloud? note that we don't worry about
    -- weak clouds if monsters are around.
    a.cloud_safe = (cloud == nil)
        or a.safe
        or danger and not cloud_is_dangerous(cloud)

    -- Equal to 10000 if the move is not closer to any stair in good_stairs,
    -- otherwise equal to the (min) dist to such a stair
    a.stair_closer = stair_improvement(pos)

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
    local best_pos, best_reason, besta
    for pos in adjacent_iter(origin) do
        local a = assess_square(pos)
        local reason = step_reason(a0, a)
        if reason then
            if besta == nil
                    or step_improvement(bestreason, reason, besta, a) then
                best_pos = pos
                besta = a
                best_reason = reason
            end
        end
    end
    if besta then
        tactical_step = delta_to_vi(best_pos)
        tactical_reason = best_reason
    end
end

function player_can_move_closer(pos)
    local orig_dist = supdist(pos)
    for dpos in adjacent_iter(origin) do
        if supdist({ x = pos.x - dpos.x, y = pos.y - dpos.y }) < orig_dist
                and feature_is_traversable(view.feature_at(dpos.x, dpos.y)) then
            return true
        end
    end
    return false
end

function mons_can_move_to_melee_player(mons)
    local name = mons:name()
    if name == "wandering mushroom"
            or name:find("vortex")
            or mons:desc():find("fleeing")
            or mons:status("paralysed")
            or mons:status("confused")
            or mons:status("petrified") then
        return false
    end

    local tab_func = function(pos)
        return mons:can_traverse(pos.x, pos.y)
    end
    local melee_range = mons:reach_range()
    return will_tab(mons:pos(), { x = 0, y = 0 }, tab_func, melee_range)
        -- If the monster can reach attack and we can't, be sure we can
        -- close the final 1-square gap.
        and (melee_range < 2
            or attack_range() > 1
            or player_can_move_closer(pos))
end

function will_tab(center, target, square_func, tab_dist)
    if not tab_dist then
        tab_dist = 1
    end

    local dpos = { x = target.x - center.x, y = target.y - center.y }
    if supdist(dpos) <= tab_dist then
        return true
    end

    local function attempt_move(pos)
        if pos.x == 0 and pos.y == 0 then
            return
        end

        local new_pos = { x = center.x + pos.x, y = center.y + pos.y }
        if supdist(newpos.x, newpos.y) > los_radius then
            return
        end

        if square_func(newpos) then
            return will_tab(newpos, target, square_func, tab_dist)
        end
    end

    local move
    if abs(dpos.x) > abs(dpos.y) then
        if abs(dpos.y) == 1 then
            move = attempt_move({ x = sign(dpos.x), y = 0 })
        end
        if not move then
            move = attempt_move({ x = sign(dpos.x), y = sign(dpos.y) })
        end
        if not move then
            move = attempt_move({ x = sign(dpos.x), y = 0 })
        end
        if not move and abs(dpos.x) > abs(dpos.y) + 1 then
             move = attempt_move({ x = sign(dpos.x), y = 1 })
        end
        if not move and abs(dpos.x) > abs(dpos.y) + 1 then
             move = attempt_move({ x = sign(dpos.x), y = -1 })
        end
        if not move then
            move = attempt_move({ x = 0, y = sign(dpos.y) })
        end
    elseif abs(dpos.x) == abs(dpos.y) then
        move = attempt_move({ x = sign(dpos.x), y = sign(dpos.y) })
        if not move then
            move = attempt_move({ x = sign(dpos.x), y = 0 })
        end
        if not move then
            move = attempt_move({ x = 0, y = sign(dpos.y) })
        end
    else
        if abs(dpos.x) == 1 then
            move = attempt_move({ x = 0, y = sign(dpos.y) })
        end
        if not move then
            move = attempt_move({ x = sign(dpos.x), y = sign(dpos.y) })
        end
        if not move then
            move = attempt_move({ x = 0, y = sign(dpos.y) })
        end
        if not move and abs(dpos.y) > abs(dpos.x) + 1 then
             move = attempt_move({ x = 1, y = sign(dpos.y) })
        end
        if not move and abs(dpos.y) > abs(dpos.x) + 1 then
             move = attempt_move({ x = -1, y = sign(dpos.y) })
        end
        if not move then
            move = attempt_move({ x = sign(dpos.x), y = 0 })
        end
    end
    return move
end