----------------------
-- Assessment of fleeing positions

function distance_map_minimum_enemy_distance(dist_map, pspeed)
    -- We ignore enemy distance in bad forms, since fleeing is always one of
    -- our best options regardless of how close monsters are.
    if in_bad_form() then
        return
    end

    local min_dist
    for _, enemy in ipairs(qw.enemy_list) do
        local map_pos = enemy:map_pos()
        local dist = dist_map.excluded_map[map_pos.x][map_pos.y]
        if dist then
            local speed_diff = enemy:speed() - pspeed
            if speed_diff > 1 then
                dist = dist / 2
            elseif speed_diff > 0 then
                dist = dist / 1.5
            end

            if enemy:is_ranged() then
                dist = dist - 4
            end

            if not min_dist or dist < min_dist then
                min_dist = dist
            end
        end
    end
    return min_dist
end

function update_flee_positions()
    qw.flee_positions = {}

    if unable_to_move() then
        return
    end

    local stairs_feats = level_stairs_features(where_branch, where_depth,
        const.dir.up)
    local search_feats = {}
    -- Only retreat to safe stairs with a safe destination.
    for _, feat in ipairs(stairs_feats) do
        local state = get_stairs(where_branch, where_depth, feat)
        local dest_state = get_destination_stairs(where_branch, where_depth,
            feat)
        if (not state or state.safe)
                and (not dest_state or dest_state.safe) then
            table.insert(search_feats, feat)
        end
    end

    local positions, feats = get_feature_map_positions(search_feats)
    if not positions then
        return
    end

    local safe_positions = {}
    for i, pos in ipairs(positions) do
        local state
        if feats[i] == "escape_hatch_up" then
            state = get_map_escape_hatch(where_branch, where_depth, pos)
        end
        if not state or state.safe then
            table.insert(safe_positions, pos)
        end
    end

    local pspeed = player_speed()
    for _, pos in ipairs(safe_positions) do
        local dist_map = get_distance_map(pos, true)
        local pdist = dist_map.excluded_map[qw.map_pos.x][qw.map_pos.y]
        local edist = distance_map_minimum_enemy_distance(dist_map, pspeed)
        if pdist and (not edist or pdist < edist) then
            if debug_channel("flee") then
                dsay("Adding flee position #"
                    .. tostring(#qw.flee_positions + 1) .. " at "
                    .. cell_string_from_map_position(pos))
            end

            table.insert(qw.flee_positions, pos)
        end
    end
end

function check_following_enemies(radius)
    return check_enemies(radius,
        function (mons)
            return mons:can_seek()
        end)
end

function want_to_flee()
    if not qw.can_flee_upstairs then
        return false
    end

    -- If we're stuck in a bad form, fleeing is our best bet.
    if in_bad_form() then
        return true
    end

    return not buffed()
        -- Don't flee from a place were we'll be opportunity attacked.
        and not check_following_enemies(1)
        and not check_allies(3)
        and (reason_to_rest(90)
            -- When we're at low XL and trying to go up, we want to flee to
            -- known stairs when autoexplore is disabled, instead of
            -- engaging in combat. This rule helps Delvers in particular
            -- avoid fights near their starting level that would get them
            -- killed.
            or you.xl() <= 8
                and disable_autoexplore
                and goal_travel.first_dir == const.dir.up)
        and starting_spell ~= "Summon Small Mammal"
end
