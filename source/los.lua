-- Coordinates and LOS

const.origin = { x = 0, y = 0 }

function supdist(pos)
    return max(abs(pos.x), abs(pos.y))
end

function feature_state(pos)
    if you.see_cell_solid_see(pos.x, pos.y) then
        return const.feat_state.reachable
    elseif you.see_cell_no_trans(pos.x, pos.y) then
        return const.feat_state.diggable
    end
    return const.feat_state.seen
end

function player_has_line_of_fire(target)
    local attack = ranged_attack(get_weapon())
    local positions = spells.path(attack.test_spell, target.x, target.y, 0, 0,
        false)
    for i, coords in ipairs(positions) do
        local pos = { x = coords[1], y = coords[2] }
        local hit_target = positions_equal(pos, target)
        local mons = get_monster_at(pos)
        if not attack.is_penetrating
                and not hit_target
                and mons
                and not mons:ignores_player_projectiles() then
            return false
        end

        if projectile_hits_non_hostile(mons) then
            return false
        end

        if hit_target then
            return true
        end
    end

    return false
end

function positions_can_reach(from_pos, to_pos)
    local dist = position_distance(from_pos, to_pos)
    if dist == 1 then
        return true
    end

    if dist == 2 then
        local x_diff = to_pos.x - from_pos.x
        local abs_x_diff = abs(x_diff)
        local y_diff = to_pos.y - from_pos.y
        local abs_y_diff = abs(y_diff)
        if abs_x_diff > abs_y_diff then
            local sign_diff = sign(x_diff)
            if abs_y_diff > 0 then
                return not is_solid_at({ x = from_pos.x + sign_diff,
                        y = from_pos.y }, true)
                    -- We know that sign(y_diff) == y_diff.
                    or not is_solid_at({ x = from_pos.x + sign_diff,
                        y = from_pos.y - y_diff }, true)
            else
                return not is_solid_at({ x = from_pos.x + sign_diff,
                    y = from_pos.y }, true)
            end

        elseif abs_x_diff < abs_y_diff then
            local sign_diff = sign(y_diff)
            if abs_x_diff > 0 then
                return not is_solid_at({ x = from_pos.x,
                        y = from_pos.y + sign_diff }, true)
                    or not is_solid_at({ x = from_pos.x - x_diff,
                        y = from_pos.y + sign_diff }, true)
            else
                return not is_solid_at({ x = from_pos.x,
                    y = from_pos.y + sign_diff }, true)
            end
        else
            return not is_solid_at({ x = from_pos.x + sign(x_diff),
                y = from_pos.y + sign(y_diff) }, true)
        end
    elseif dist >= 3 then
        return cell_see_cell(from_pos, to_pos)
    end
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
        radius = qw.los_radius
    end
    assert(radius > 0, "Radius must be a positive integer.")

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

function position_distance(a, b)
    return supdist(position_difference(a, b))
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

function cell_see_cell(a, b)
    return position_distance(a, b) <= qw.los_radius
        and view.cell_see_cell(a.x, a.y, b.x, b.y)
end
