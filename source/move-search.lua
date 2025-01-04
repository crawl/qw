----------------------
-- The movement search algorithm.

const.max_search_radius = 14

function traversal_function(assume_flight)
    return function(pos)
        -- XXX: This needs to run before update_map() and hence before
        -- traversal_map is updated, so we have to do an uncached check.
        -- Ideally we'd use the traversal map, but this requires separating
        -- the traversal map update to its own path and somehow retaining
        -- information about the per-cell changes so update_map() can
        -- propagate updates to adjacent cells.
        return feature_is_traversable(view.feature_at(pos.x, pos.y),
            assume_flight)
    end
end

function tab_function(assume_flight)
    return function(pos)
        local mons = get_monster_at(pos)
        if mons and not mons:is_harmless() then
            return false
        end

        return is_safe_at(pos, assume_flight)
            and not view.withheld(pos.x, pos.y)
    end
end

function search_from(search, pos, current, is_deviation)
    local hash = hash_position(pos)
    if search.seen[hash] then
        return false
    end

    local cur_deviations = search.num_deviations + (is_deviation and 1 or 0)

    if debug_channel("move-all") then
        dsay("Checking "
            .. (is_deviation and "deviation(" .. cur_deviations .. ") " or "")
            .. "move from " .. cell_string_from_position(current)
            .. " to " .. cell_string_from_position(pos))
    end

    local cache = search.cache[hash]
    if cache then
        local result
        if cache and cache.path then
            for _, ppos in ipairs(cache.path) do
                table.insert(search.path, ppos)
                search.dist = search.dist + 1
            end

            result = true
        elseif not cache
                or cache.deviations_failed
                    and cache.deviations_failed <= cur_deviations then
            result = false
        end

        if result ~= nil then
            if debug_channel("move-all") then
                dsay("Cached move search result: "
                    .. (result and "success" or "failure"))
            end

            return result
        end
    end

    if position_distance(search.center, pos) > const.max_search_radius then
        if debug_channel("move-all") then
            dsay("Search traveled past max search radius of "
                .. const.max_search_radius)
        end

        search.cache[hash] = false
        return false
    end

    if cur_deviations > 4 then
        if debug_channel("move-all") then
            dsay("Too many deviation movements")
        end

        search.cache[hash] = { deviations_failed = cur_deviations }
        return false
    end

    if search.square_func(pos) then
        search.dist = search.dist + 1
        search.num_deviations = cur_deviations

        table.insert(search.path, pos)
        search.seen[hash] = true
        local cur_i = #search.path

        if do_move_search(search, pos) then
            cache = { path = {} }
            for i = cur_i, #search.path do
                table.insert(cache.path, search.path[i])
            end
            search.cache[hash] = cache
            return true
        else
            search.path[#search.path] = nil
            search.seen[hash] = nil

            search.dist = search.dist - 1
            if is_deviation then
                search.num_deviations = search.num_deviations - 1
            end

            search.cache[hash] = { deviations_failed = cur_deviations }
            return false
        end
    end

    if debug_channel("move-all") then
        dsay("Square function failed")
    end

    search.cache[hash] = { deviations_failed = cur_deviations }
    return false
end

function do_move_search(search, current)
    local diff = position_difference(search.target, current)
    local dist = supdist(diff)
    if dist == 0
            or search.min_dist > 0
                and positions_can_melee(current, search.target,
                    search.min_dist) then
        search.move = position_difference(search.path[2], search.center)
        return true
    end

    local pos
    local sign_diff_x = sign(diff.x)
    local sign_diff_y = sign(diff.y)
    pos = { x = current.x + sign_diff_x, y = current.y + sign_diff_y }
    if search_from(search, pos, current) then
        return true
    end

    pos = { x = current.x + sign_diff_x, y = current.y }
    if search_from(search, pos, current) then
        return true
    end

    pos = { x = current.x, y = current.y + sign_diff_y }
    if search_from(search, pos, current) then
        return true
    end

    local abs_diff_x = abs(diff.x)
    local abs_diff_y = abs(diff.y)
    if abs_diff_x >= abs_diff_y then
        if abs_diff_y > 0 then
            pos = { x = current.x + sign_diff_x, y = current.y - sign_diff_y }
            if search_from(search, pos, current, true) then
                return true
            end

            pos = { x = current.x - sign_diff_x, y = current.y + sign_diff_y }
            if search_from(search, pos, current, true) then
                return true
            end
        else
            pos = { x = current.x + sign_diff_x, y = current.y + 1 }
            if search_from(search, pos, current, true) then
                return true
            end

            pos = { x = current.x + sign_diff_x, y = current.y - 1 }
            if search_from(search, pos, current, true) then
                return true
            end

            pos = { x = current.x, y = current.y + 1 }
            if search_from(search, pos, current, true) then
                return true
            end

            pos = { x = current.x, y = current.y - 1 }
            if search_from(search, pos, current, true) then
                return true
            end
        end
    elseif abs_diff_x < abs_diff_y then
        if abs_diff_x > 0 then
            pos = { x = current.x - sign_diff_x, y = current.y + sign_diff_y }
            if search_from(search, pos, current, true) then
                return true
            end

            pos = { x = current.x + sign_diff_x, y = current.y - sign_diff_y }
            if search_from(search, pos, current, true) then
                return true
            end
        else
            pos = { x = current.x + 1, y = current.y + sign_diff_y }
            if search_from(search, pos, current, true) then
                return true
            end

            pos = { x = current.x - 1, y = current.y + sign_diff_y }
            if search_from(search, pos, current, true) then
                return true
            end

            pos = { x = current.x + 1, y = current.y }
            if search_from(search, pos, current, true) then
                return true
            end

            pos = { x = current.x - 1, y = current.y }
            if search_from(search, pos, current, true) then
                return true
            end
        end
    end

    return false
end

function move_search(center, target, square_func, min_dist, cache)
    if not min_dist then
        min_dist = 0
    end

    if positions_equal(center, target)
            or min_dist > 0
                and positions_can_melee(center, target, min_dist) then
        return
    end

    if debug_channel("move-all") then
        dsay("Move search from " .. cell_string_from_position(center)
            .. " to " .. cell_string_from_position(target)
            .. " with min distance " .. min_dist)
    end

    search = { center = center, target = target, square_func = square_func,
        min_dist = min_dist, dist = 0, path = { center },
        seen = { [hash_position(center)] = true }, num_deviations = 0 }

    if cache then
        search.cache = cache
    else
        search.cache = {}
    end

    if do_move_search(search, center) then
        return search
    end
end
