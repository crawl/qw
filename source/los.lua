-- Coordinates and LOS

-- Feature LOS state enum
FEAT_LOS = {
    "NONE",
    "SEEN",
    "DIGGABLE",
    "REACHABLE",
    "EXPLORED",
}

function los_state(x, y)
    if you.see_cell_solid_see(x, y) then
        return FEAT_LOS.REACHABLE
    elseif you.see_cell_no_trans(x, y) then
        return FEAT_LOS.DIGGABLE
    end
    return FEAT_LOS.SEEN
end

function square_iter(x, y, radius, include_center)
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

        return x + dx, y + dy
    end
end

function adjacent_iter(x, y, include_center)
    return square_iter(x, y, 1, include_center)
end

local square = {
    {1, -1}, {1, 1}, {-1, 1}, {-1, -1}
}

local square_move = {
    {0, 1}, {-1, 0}, {0, -1}, {1, 0}
}

function radius_iter(x, y, radius, include_center)
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
                return 0, 0
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

        return x + dx, y + dy
    end
end

function hash_coordinates(x, y)
    return 2 * GXM * x + y
end

function hash_position(pos)
    return hash_coordinates(pos.x, pos.y)
end

function unhash_position(hash)
    local x = math.floor(hash / (2 * GXM) + 0.5)
    local y = hash - 2 * GXM * x
    return { x = x, y = y }
end
