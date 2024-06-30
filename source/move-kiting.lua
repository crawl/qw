----------------------
-- Assessment of kiting positions

function kiting_attack_delay()
    local target = get_ranged_target()
    if not target then
        target = get_melee_target()
        if not target then
            return
        end
    end

    return player_attack_delay(target.attack.index)
end

function enemy_needs_attack_distance(enemy, attack_delay)
    if not enemy:has_path_to_melee_player() then
        return false
    end

    return math.ceil(attack_delay / enemy:move_delay())
        >= enemy:melee_move_distance(const.origin)
end

function enemy_allows_kiting(enemy, attack_delay, move_delay)
    if enemy:is_ranged(true) or enemy:los_danger() then
        if debug_channel("kite") then
            local props = { los_danger = "los danger", is_ranged = "ranged" }
            dsay("Unable to kite due to LOS danger or ranged: "
                .. monster_string(enemy, props))
        end

        return false
    end

    if not enemy_needs_attack_distance(enemy, attack_delay) then
        return true
    end

    if enemy:move_delay() <= move_delay then
        if debug_channel("kite") then
            local props = { move_delay = "move delay" }
            dsay("Unable to kite because we are not faster than nearby"
                .. " monster: " .. monster_string(enemy, props))
        end

        return false
    end

    local moves_needed = move_delay / (enemy:move_delay() - move_delay)
    if moves_needed > 6 then
        if debug_channel("kite") then
            local props = { move_delay = "move delay" }
            dsay("Unable to kite since nearby monster requires too many moves"
                .. " to gain distance (" .. tostring(moves_needed) .. "): "
                .. monster_string(enemy, props))
        end

        return false
    end

    return true
end

function want_to_kite()
    if qw.want_to_kite ~= nil then
        return qw.want_to_kite
    end

    qw.want_to_kite = false
    qw.want_to_kite_step = false

    if hp_is_low(50) or you.confused() or in_branch("Abyss") then
        return false
    end

    local enemies = assess_enemies(const.duration.ignore_buffs)
    if enemies.threat < moderate_threat_level()
            and not enemies.scary_enemy then
        return false
    end

    local target = get_ranged_target()
    if not target then
        target = get_melee_target()
        if not target then
            return false
        end

        local enemy = get_monster_at(target.pos)
        if not enemy or enemy:reach_range() >= player_reach_range() then
            return false
        end
    end

    local attack_delay = kiting_attack_delay()
    local move_delay = player_move_delay()

    if debug_channel("kite") then
        dsay("Evaluating kiting with attack delay " .. tostring(attack_delay)
            .. " and move delay " .. tostring(move_delay))
    end

    for _, enemy in ipairs(qw.enemy_list) do
        if debug_channel("kite-all") then
            local props = { los_danger = "los danger", is_ranged = "ranged",
                reach_range = "reach", move_delay = "move delay" }
            dsay("Evaluating " .. monster_string(enemy, props))
        end

        if not enemy_allows_kiting(enemy, attack_delay, move_delay) then
            return false
        end

        -- We take a kiting step if an attack would put us within range of the
        -- monster's melee.
        if not qw.want_to_kite_step
                and enemy_needs_attack_distance(enemy, attack_delay) then
            if debug_channel("kite") then
                local props = { reach_range = "reach",
                    move_delay = "move delay" }
                dsay("Want a kiting step due to nearby "
                    .. monster_string(enemy, props))
            end

            qw.want_to_kite_step = true
        end
    end

    qw.want_to_kite = true
    return true
end

function want_to_kite_step()
    return want_to_kite() and qw.want_to_kite_step
end

function will_kite()
    return want_to_kite()
        and (not want_to_kite_step()
            or qw.tactical_reason == "kiting")
end

function kiting_function(pos)
    return not get_monster_at(pos)
        and not view.withheld(pos.x, pos.y)
        and is_safe_at(pos)
        and (intrinsic_amphibious() or not in_water_at(pos))
end

function assess_kiting_enemy_at(pos, enemy, player_search)
    local result = { avoid_score = 0, see_score = 0, dist_score = 0 }

    if debug_channel("kite-all") then
        local props = { reach_range = "reach", move_delay = "move delay" }
        dsay("Assessing " .. monster_string(enemy, props))
    end

    if not enemy:has_path_to_melee_player() then
        if debug_channel("kite-all") then
            dsay("Ignoring enemy: no path to melee player")
        end

        return result
    end

    local enemy_move_dist = enemy:melee_move_distance(pos)
    if enemy:can_seek(true) and enemy_move_dist == const.inf_dist then
        if debug_channel("kite-all") then
            dsay("Position rejected: " .. enemy:name()
                .. " can't reach this position")
        end

        return
    end

    local move_delay = player_move_delay()
    local attack_delay = kiting_attack_delay()
    local gained_dist = enemy_move_dist
        - player_search.dist * move_delay / enemy:move_delay()
    local min_gain = math.ceil(attack_delay / enemy:move_delay())

    if debug_channel("kite-all") then
        dsay(enemy:name() .. " at " .. pos_string(enemy:pos())
            .. " has move distance " .. tostring(enemy_move_dist)
            .. " and a distance gain of " .. tostring(gained_dist)
            .. " and needs a distance gain of at least "
            .. tostring(min_gain))
    end

    if gained_dist < min_gain then
        if debug_channel("kite-all") then
            dsay("Position rejected: distance gain of " .. enemy:name()
                .. " below minimum required")
        end

        return
    end

    local last_pos
    if enemy:can_melee_player() then
        last_pos = enemy:pos()
    else
        last_pos = enemy:melee_move_search(const.origin).last_pos
    end

    local avoid_score = position_distance(last_pos, player_search.first_pos)
    if enemy:can_melee_player()
            and enemy:reach_range() > 1
            and not enemy:can_melee_at(player_search.first_pos, last_pos) then
        avoid_score = avoid_score + 0.5
    end

    local threat = enemy:threat(const.duration.ignore_buffs)
    result.avoid_score = result.avoid_score + threat * avoid_score
    result.see_score = result.see_score
        + threat * (cell_see_cell(player_search.first_pos, enemy:pos()) and 1 or 0)
    result.dist_score = result.dist_score + threat * gained_dist

    return result
end

function assess_kiting_destination(pos)
    if supdist(pos) < 3 then
        return false
    end

    local search = move_search(const.origin, pos, kiting_function, 0)
    if not search then
        return
    end

    local map_pos = position_sum(qw.map_pos, pos)
    for lpos in square_iter(pos, qw.los_radius) do
        local map_lpos = position_sum(qw.map_pos, lpos)
        if supdist(map_lpos) <= const.gxm
                and traversal_map[map_lpos.x][map_lpos.y] == nil
                and cell_see_cell(pos, lpos) then
            return false
        end
    end

    if debug_channel("kite-all") then
        dsay("Assessing kiting destination " .. cell_string_from_position(pos)
            .. " with move distance " .. tostring(search.dist))
    end

    local result = { pos = pos, map_pos = map_pos, dist = search.dist,
        kite_step = search.first_pos, avoid_score = 0, see_score = 0,
        dist_score = 0 }
    for _, enemy in ipairs(qw.enemy_list) do
        local eresult = assess_kiting_enemy_at(pos, enemy, search)
        if not eresult then
            return
        end

        result.avoid_score = result.avoid_score + eresult.avoid_score
        result.see_score = result.see_score + eresult.see_score
        result.dist_score = result.dist_score + eresult.dist_score
    end

    if debug_channel("kite-all") then
        dsay("Destination has an avoidance score of "
            .. tostring(result.avoid_score)
            .. ", a sight score of "
            .. tostring(result.see_score)
            .. ", and a distance score of "
            .. tostring(result.dist_score))
    end

    return result
end

function result_improves_kiting(result, best_result)
    if not result then
        return false
    end

    if not best_result then
        return true
    end

    return compare_table_keys(result, best_result,
        { "avoid_score", "see_score", "dist_score" })
end

function best_kiting_destination_func()
    if debug_channel("kite") then
        dsay("Assessing kiting destinations with attack delay "
            .. tostring(kiting_attack_delay()) .. " and move delay "
            .. tostring(player_move_delay()))
    end

    local best_result
    for pos in square_iter(const.origin, qw.los_radius) do
        local result = assess_kiting_destination(pos)
        if result_improves_kiting(result, best_result) then
            best_result = result
        end
    end

    if debug_channel("kite") then
        if best_result then
            dsay("Found kiting destination at "
                .. cell_string_from_position(best_result.pos)
                .. " at distance " .. tostring(best_result.dist)
                .. " with an avoidance score of "
                .. tostring(best_result.avoid_score)
                .. " with a sight score of "
                .. tostring(best_result.see_score)
                .. " and a distance score of "
                .. tostring(best_result.dist_score))
        else
            dsay("No kiting destination found")
        end
    end

    return best_result
end

function best_kiting_destination()
    return turn_memo("best_kiting_destination", best_kiting_destination_func)
end

function is_kite_step(pos)
    if not want_to_kite_step() then
        return false
    end

    local result = best_kiting_destination()
    if not result then
        return false
    end

    return positions_equal(result.kite_step, pos)
end
