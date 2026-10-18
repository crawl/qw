----------------------
-- General movement search algorithms used for monsters.

const.max_search_radius = 14
const.max_search_deviations = 4

function search_to(search, pos, current, is_deviation)
    if search.seen[pos.hash] then
        return false
    end

    local cur_deviations = search.num_deviations + (is_deviation and 1 or 0)

    if debug_channel("move-search") then
        dsay("Checking "
            .. (is_deviation and "deviation(" .. cur_deviations .. ") " or "")
            .. "move from " .. cell_string_from_position(current)
            .. " to " .. cell_string_from_position(pos))
    end

    local cache = search.cache[pos.hash]
    if cache then
        local result
        if cache.path then
            for _, ppos in ipairs(cache.path) do
                table.insert(search.path, ppos)
                search.dist = search.dist + 1
            end

            result = true
        elseif cache.deviations_failed
                    and cache.deviations_failed <= cur_deviations then
            result = false
        end

        if result ~= nil then
            if debug_channel("move-search") then
                dsay("Cached move search result: "
                    .. (result and "success" or "failure"))
            end

            return result
        end
    end

    if position_distance(search.center, pos) > const.max_search_radius then
        if debug_channel("move-search") then
            dsay("Search traveled past max search radius of "
                .. const.max_search_radius)
        end

        search.cache[pos.hash] = false
        return false
    end

    if cur_deviations > const.max_search_deviations then
        if debug_channel("move-search") then
            dsay("Too many deviation movements")
        end

        search.cache[pos.hash] = { deviations_failed = cur_deviations }
        return false
    end

    if search.move_func(pos) then
        -- The seen table is only updated when we can successfully continue the
        -- recursive search. It prevents revisiting a succesfully traversed
        -- square in the same path.
        search.seen[pos.hash] = true
        search.dist = search.dist + 1
        search.num_deviations = cur_deviations

        table.insert(search.path, pos)
        local cur_i = #search.path

        if do_move_search(search, pos) then
            cache = { path = {} }
            for i = cur_i, #search.path do
                table.insert(cache.path, search.path[i])
            end
            search.cache[pos.hash] = cache

            return true
        else
            search.path[#search.path] = nil
            search.seen[pos.hash] = nil
            search.dist = search.dist - 1

            if is_deviation then
                search.num_deviations = search.num_deviations - 1
            end

            search.cache[pos.hash] = { deviations_failed = cur_deviations }

            return false
        end
    end

    if debug_channel("move-search") then
        dsay("Square function failed")
    end

    search.cache[pos.hash] = { deviations_failed = cur_deviations }
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

    local sign_diff_x = sign(diff.x)
    local sign_diff_y = sign(diff.y)
    local pos = position_coord_sum(current, sign_diff_x, sign_diff_y)
    if search_to(search, pos, current) then
        return true
    end

    pos = position_coord_sum(current,  sign_diff_x, 0)
    if search_to(search, pos, current) then
        return true
    end

    pos = position_coord_sum(current, 0, sign_diff_y)
    if search_to(search, pos, current) then
        return true
    end

    local abs_diff_x = abs(diff.x)
    local abs_diff_y = abs(diff.y)
    if abs_diff_x >= abs_diff_y then
        if abs_diff_y > 0 then
            pos = position_coord_sum(current, sign_diff_x, -sign_diff_y)
            if search_to(search, pos, current, true) then
                return true
            end

            pos = position_coord_sum(current, -sign_diff_x, sign_diff_y)
            if search_to(search, pos, current, true) then
                return true
            end
        else
            pos = position_coord_sum(current, sign_diff_x, 1)
            if search_to(search, pos, current, true) then
                return true
            end

            pos = position_coord_sum(current, sign_diff_x, -1)
            if search_to(search, pos, current, true) then
                return true
            end

            pos = position_coord_sum(current, 0, 1)
            if search_to(search, pos, current, true) then
                return true
            end

            pos = position_coord_sum(current, 0, -1)
            if search_to(search, pos, current, true) then
                return true
            end
        end
    elseif abs_diff_x < abs_diff_y then
        if abs_diff_x > 0 then
            pos = position_coord_sum(current, -sign_diff_x, sign_diff_y)
            if search_to(search, pos, current, true) then
                return true
            end

            pos = position_coord_sum(current, sign_diff_x, -sign_diff_y)
            if search_to(search, pos, current, true) then
                return true
            end
        else
            pos = position_coord_sum(current, 1, sign_diff_y)
            if search_to(search, pos, current, true) then
                return true
            end

            pos = position_coord_sum(current, -1, sign_diff_y)
            if search_to(search, pos, current, true) then
                return true
            end

            pos = position_coord_sum(current, 1, 0)
            if search_to(search, pos, current, true) then
                return true
            end

            pos = position_coord_sum(current, -1, 0)
            if search_to(search, pos, current, true) then
                return true
            end
        end
    end

    return false
end

function move_search(center, target, move_func, min_dist, cache)
    if not min_dist then
        min_dist = 0
    end

    if positions_equal(center, target)
            or min_dist > 0
                and positions_can_melee(center, target, min_dist) then
        return
    end

    if debug_channel("move-search") then
        dsay("Move search from " .. cell_string_from_position(center)
            .. " to " .. cell_string_from_position(target)
            .. " with min distance " .. min_dist)
    end

    search = { center = center, target = target, move_func = move_func,
        min_dist = min_dist, dist = 0, path = { center },
        seen = { [center.hash] = true }, num_deviations = 0 }

    if cache then
        search.cache = cache
    else
        search.cache = {}
    end

    if do_move_search(search, center) then
        return search
    end
end
