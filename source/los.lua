-- Coordinates and LOS

const.origin = { x = 0, y = 0 }

function supdist(pos)
    return max(abs(pos.x), abs(pos.y))
end

function is_adjacent(pos)
    return abs(pos.x) <= 1 and abs(pos.y) <= 1
end

function feature_state(pos)
    if you.see_cell_solid_see(pos.x, pos.y) then
        return const.feat_state.reachable
    elseif you.see_cell_no_trans(pos.x, pos.y) then
        return const.feat_state.diggable
    end
    return const.feat_state.seen
end

function have_line_of_fire(pos)
    return you.see_cell_solid_see(pos.x, pos.y)
end

function square_iter(pos, radius, include_center)
    if not radius then
        radius = los_radius
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

        return { x = pos.x + dx, y = pos.y + dy }
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

function radius_iter(pos, radius, include_center)
    if not radius then
        radius = los_radius
    end
    if radius <= 0 then
        error("Radius must be a positive integer.")
    end

    local r = 0
    local i = 1
    local dx, dy = 0, 0
    return function()
        if r == 0 then
            r = 1
            if include_center then
                return pos
            end
        end

        local last_point = i == #square + 1
        if last_point
                and dx + square_move[i - 1][1] == r * square[1][1]
                and dy + square_move[i - 1][2] == r * square[1][2]
            or not last_point
                and dx == r * square[i][1]
                and dy == r * square[i][2] then

            if last_point then
                r = r + 1
                if r > radius then
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

        return { x = pos.x + dx, y = pos.y + dy }
    end
end

function hash_position(pos)
    return 2 * const.gxm * pos.x + pos.y
end

function unhash_position(hash)
    local x = math.floor(hash / (2 * const.gxm) + 0.5)
    return { x = x, y = hash - 2 * const.gxm * x }
end

function is_adjacent(pos, center)
    if not center then
        center = const.origin
    end

    return max(abs(pos.x - center.x), abs(pos.y - center.y)) == 1
end

function position_difference(a, b)
    return { x = a.x - b.x, y = a.y - b.y }
end

function position_sum(a, b)
    return { x = a.x + b.x, y = a.y + b.y }
end

function positions_equal(a, b)
    return a.x == b.x and a.y == b.y
end

function position_is_origin(a)
    return a.x == 0 and a.y == 0
end
