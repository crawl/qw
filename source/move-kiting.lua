----------------------
-- Assessment of kiting positions

function kiting_attack_delay()
    local target = best_ranged_target()
    -- Due to opportunity attacks, Rift is the only melee weapon we could ever
    -- kite with.
    if not target and player_melee_range() > 2 then
        target = best_melee_target()
        if not target then
            return
        end

        local enemy = get_monster_at(target.pos)
        if enemy:melee_range() >= enemy:player_melee_range() - 1 then
            return
        end
    end

    if not target then
        return
    end

    -- We don't want to consider temporary haste, since this is not a buff we
    -- should waste by kiting. Durations like Heroism and even Finesse are more
    -- numerous, but future work on kiting might want to consider these more
    -- carefully as well.
    return player_attack_delay(target.attack.index, const.duration.active,
        "haste")
end

function enemy_needs_attack_distance(enemy, attack_delay)
    if not enemy:has_path_to_melee_player() then
        return false
    end

    return math.ceil(attack_delay / enemy:move_delay())
        >= enemy:melee_move_distance(const.origin)
end

function enemy_allows_kiting(enemy, attack_delay, move_delay)
    if enemy:is_ranged() or enemy:los_danger() then
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
            dsayf("Unable to kite since nearby monster requires too many moves"
                    .. " (%d) to gain distance: %s",
                moves_needed,
                monster_string(enemy, props))
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
    if enemies.threat < moderate_threat_level() then
        return false
    end

    local attack_delay = kiting_attack_delay()
    if not attack_delay then
        return false
    end

    local move_delay = player_move_delay()

    if debug_channel("kite") then
        dsay("Evaluating kiting with attack delay " .. attack_delay
            .. " and move delay " .. move_delay)
    end

    for _, enemy in ipairs(qw.enemy_list) do
        if debug_channel("kite-all") then
            dsay("Evaluating " .. monster_string(enemy))
        end

        if not enemy_allows_kiting(enemy, attack_delay, move_delay) then
            return false
        end

        -- We take a kiting step if an attack would put us within range of the
        -- monster's melee.
        if not qw.want_to_kite_step
                and enemy_needs_attack_distance(enemy, attack_delay) then
            if debug_channel("kite") then
                dsay("Want a kiting step due to nearby "
                    .. monster_string(enemy))
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

function kiting_move_check(pos)
    return is_safe_at(pos, true)
        and (intrinsic_amphibious() or not in_water_at(pos))
end

function assess_kiting_enemy_at(pos, enemy, player_path)
    local result = { avoid_score = 0, see_score = 0, dist_score = 0 }

    if debug_channel("kite-all") then
        dsay("Assessing " .. monster_string(enemy))
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
            dsayf("Position rejected: %s can't reach this position",
                enemy:name())
        end

        return
    end

    local attack_delay = kiting_attack_delay()
    local move_delay = player_move_delay()
    local gained_dist = enemy_move_dist
        - (#player_path - 1) * move_delay / enemy:move_delay()
    local min_gain = math.ceil(attack_delay / enemy:move_delay())

    if debug_channel("kite-all") then
        dsayf("Enemy at %s has move distance %d, a distance gain of %d"
                .. ", and needs a gain of at least %d",
            cell_string_from_position(enemy:pos()),
            enemy_move_dist,
            gained_dist,
            min_gain)
    end

    if gained_dist < min_gain then
        if debug_channel("kite-all") then
            dsayf("Position rejected: gain of %d below minimum required",
                gained_dist)
        end

        return
    end

    local last_pos
    if enemy:can_melee_player() then
        last_pos = enemy:pos()
    else
        local search = enemy:melee_move_search(const.origin)
        last_pos = search.path[#search.path]
    end

    local first_pos = los_position(player_path[2])
    local avoid_score = position_distance(last_pos, first_pos)
    if enemy:can_melee_player()
            and enemy:melee_range() > 1
            and not enemy:can_melee_at(first_pos, last_pos) then
        avoid_score = avoid_score + 0.5
    end

    local threat = enemy:threat(const.duration.ignore_buffs)
    result.avoid_score = result.avoid_score + threat * avoid_score
    result.see_score = result.see_score
        + threat * (cell_see_cell(first_pos, enemy:pos()) and 1 or 0)
    result.dist_score = result.dist_score + threat * gained_dist

    return result
end

function assess_kiting_destination(pos)
    if supdist(pos) < 3 then
        return false
    end

    local player_path = move_path(const.move.kiting, map_position(pos))
    if not player_path then
        return
    end

    for lpos in square_iter(pos, qw.los_radius) do
        if map_is_unseen_at(map_position(lpos))
                and cell_see_cell(pos, lpos) then
            return false
        end
    end

    if debug_channel("kite-all") then
        dsayf("Assessing kiting destination %s with move distance %d",
            cell_string_from_position(pos), #player_path - 1)
    end

    local result = { pos = pos, map_pos = map_position(pos),
        dist = #player_path - 1, kite_step = los_position(player_path[2]),
        avoid_score = 0, see_score = 0, dist_score = 0 }
    for _, enemy in ipairs(qw.enemy_list) do
        local eresult = assess_kiting_enemy_at(pos, enemy, player_path)
        if not eresult then
            return
        end

        result.avoid_score = result.avoid_score + eresult.avoid_score
        result.see_score = result.see_score + eresult.see_score
        result.dist_score = result.dist_score + eresult.dist_score
    end

    if debug_channel("kite-all") then
        dsayf("Destination has an avoidance score of %d, a sight score of %d"
                .. ", and a distance score of %d",
            result.avoid_score,
            result.see_score,
            result.dist_score)
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
        dsayf("Assessing kiting destinations with attack/move delays %s/%s",
            kiting_attack_delay(),
            player_move_delay())
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
            dsayf("Found kiting destination at %s at distance %d with an"
                    .. " avoidance/sight/distance scores of %d/%d/%d",
                cell_string_from_position(best_result.pos),
                best_result.dist,
                best_result.avoid_score,
                best_result.see_score,
                best_result.dist_score)
        else
            dsay("No kiting destination found")
        end
    end

    return best_result
end

function best_kiting_destination()
    return turn_memo(best_kiting_destination_func)
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
