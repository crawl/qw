-- Coordinates and LOS

-- LOS origin.
const.origin = new_position(0, 0)

function supdist(pos)
    return max(abs(pos.x), abs(pos.y))
end

function feature_state(pos)
    if you.see_cell_solid_see(pos.x, pos.y) then
        return const.explore.reachable
    elseif you.see_cell_no_trans(pos.x, pos.y) then
        return const.explore.diggable
    end
    return const.explore.seen
end

function positions_can_melee(from_pos, to_pos, range)
    local dist = position_distance(from_pos, to_pos)
    if dist == 0 then
        return false
    end

    assert(range > 0 and range <= 3)

    if dist > range then
        return false
    elseif dist == 1 then
        return true
    -- Rift is smite-targeted.
    elseif range == 3 then
        return cell_see_cell(from_pos, to_pos)
    end

    -- At this point we know that dist = range = 2.
    local x_diff = to_pos.x - from_pos.x
    local abs_x_diff = abs(x_diff)
    local y_diff = to_pos.y - from_pos.y
    local abs_y_diff = abs(y_diff)
    if abs_x_diff > abs_y_diff then
        local sign_diff = sign(x_diff)
        if abs_y_diff > 0 then
            return not is_solid_at(
                new_position(from_pos.x + sign_diff, from_pos.y), true)
                -- We know that sign(y_diff) == y_diff.
                or not is_solid_at(
                    new_position(from_pos.x + sign_diff, from_pos.y + y_diff),
                    true)
        else
            return not is_solid_at(
                new_position(from_pos.x + sign_diff, from_pos.y), true)
        end
    elseif abs_x_diff < abs_y_diff then
        local sign_diff = sign(y_diff)
        if abs_x_diff > 0 then
            return not is_solid_at(
                new_position(from_pos.x, from_pos.y + sign_diff), true)
                or not is_solid_at(
                    new_position(from_pos.x - x_diff, from_pos.y + sign_diff),
                    true)
        else
            return not is_solid_at(
                new_position(from_pos.x, from_pos.y + sign_diff), true)
        end
    else
        return not is_solid_at(
            new_position(from_pos.x + sign(x_diff), from_pos.y + sign(y_diff)),
            true)
    end
end

function position_from_hash(hash)
    local x = math.floor(hash / (2 * const.gxm) + 0.5)
    return new_position(x, hash - 2 * const.gxm * x)
end

function square_iter(pos, radius, include_center)
    if not radius then
        radius = qw.los_radius
    end
    if radius <= 0 then
        error("Radius must be a positive integer.")
    end

    local dx = -radius
    local dy = -radius - 1
    return function()
        if dy == radius then
            if dx == radius then
                return
            else
                dx = dx + 1
                dy = -radius
            end
        else
            dy = dy + 1
            if not include_center and dx == 0 and dy == 0 then
                dy = dy + 1
            end
        end

        return new_position(pos.x + dx, pos.y + dy)
    end
end

function adjacent_iter(pos, include_center)
    return square_iter(pos, 1, include_center)
end


local square = {
    {1, -1}, {1, 1}, {-1, 1}, {-1, -1}
}

local square_move = {
    {0, 1}, {-1, 0}, {0, -1}, {1, 0}
}

function radius_iter(pos, radius, include_center, reverse_radius)
    if not radius then
        radius = qw.los_radius
    end
    assert(radius > 0, "Radius must be a positive integer.")

    local r = reverse_radius and radius or 0
    local i = 1
    local dx, dy = 0, 0
    return function()
        if r == 0 then
            -- If we reached here under reverse_radius, we returned the center
            -- last iteration, so we're done.
            if reverse_radius then
                return
            end

            r = 1
            if include_center then
                return pos
            end
        end

        local last_point = i == #square + 1
        if last_point and dx + square_move[i - 1][1] == r * square[1][1]
                    and dy + square_move[i - 1][2] == r * square[1][2]
                or not last_point
                    and dx == r * square[i][1]
                    and dy == r * square[i][2] then

            if last_point then
                r = r + (reverse_radius and -1 or 1)
                if reverse_radius and r == 0 then
                    return include_center and pos or nil
                end

                if not reverse_radius and r > radius then
                    return
                end

                i = 1
            else
                i = i + 1
            end
        end

        if i == 1 then
            dx = r * square[1][1]
            dy = r * square[1][2]
        else
            dx = dx + square_move[i - 1][1]
            dy = dy + square_move[i - 1][2]
        end

        return new_position(pos.x + dx, pos.y + dy)
    end
end

function is_adjacent(pos, center)
    if not center then
        center = const.origin
    end

    return max(abs(pos.x - center.x), abs(pos.y - center.y)) == 1
end

function position_distance(a, b)
    return supdist(position_difference(a, b))
end

function position_difference(a, b)
    return new_position(a.x - b.x, a.y - b.y)
end

function position_sum(a, b)
    return new_position(a.x + b.x, a.y + b.y)
end

function position_coord_sum(pos, x, y)
    return new_position(pos.x + x, pos.y + y)
end

function positions_equal(a, b)
    return a.x == b.x and a.y == b.y
end

function position_is_origin(a)
    return a.x == 0 and a.y == 0
end

function map_position(pos)
    return position_sum(qw.map_pos, pos)
end

function los_position(map_pos)
    return position_difference(map_pos, qw.map_pos)
end

function cell_see_cell_func(a, b)
    return view.cell_see_cell(a.x, a.y, b.x, b.y)
end

function cell_see_cell(a, b)
    return turn_memo_args(cell_see_cell_func, a, b)
end

function map_cell_see_cell(a, b)
    return cell_see_cell(map_position(a), map_position(b))
end
