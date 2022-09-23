--------------------
-- Utility functions

function contains_string_in(name, t)
    for _, value in ipairs(t) do
        if string.find(name, value) then
            return true
        end
    end
    return false
end

function split(str, del)
    local res = { }
    local v
    for v in string.gmatch(str, "([^" .. del .. "]+)") do
        table.insert(res, v)
    end
    return res
end

function bool_string(x)
    return x and "true" or "false"
end

function capitalize(str)
    local lower = str:lower()
    return lower:sub(1, 1):upper() .. lower:sub(2)
end

-- Remove leading and trailing whitespace.
function trim(str)
    return str:gsub("^%s+", ""):gsub("%s+$", "")
end

function control(c)
    return string.char(string.byte(c) - string.byte('a') + 1)
end

function arrowkey(c)
    local a2c = { ['u'] = -254, ['d'] = -253, ['l'] = -252 ,['r'] = -251 }
    return a2c[c]
end

function delta_to_vi(dx, dy)
    local d2v = {
        [-1] = { [-1] = 'y', [0] = 'h', [1] = 'b'},
        [0]    = { [-1] = 'k',                        [1] = 'j'},
        [1]    = { [-1] = 'u', [0] = 'l', [1] = 'n'},
    }
    return d2v[dx][dy]
end

function vi_to_delta(c)
    local d2v = {
        [-1] = { [-1] = 'y', [0] = 'h', [1] = 'b'},
        [0]    = { [-1] = 'k',                        [1] = 'j'},
        [1]    = { [-1] = 'u', [0] = 'l', [1] = 'n'},
    }
    for x = -1, 1 do
        for y = -1, 1 do
            if supdist(x, y) > 0 and d2v[x][y] == c then
                return x, y
            end
        end
    end
end

function sign(a)
    return a > 0 and 1 or a < 0 and -1 or 0
end

function abs(a)
    return a * sign(a)
end

function vector_move(dx, dy)
    local str = ''
    for i = 1, abs(dx) do
        str = str .. delta_to_vi(sign(dx), 0)
    end
    for i = 1, abs(dy) do
        str = str .. delta_to_vi(0, sign(dy))
    end
    return str
end

function max(x, y)
    if x > y then
        return x
    else
        return y
    end
end

function min(x, y)
    if x < y then
        return x
    else
        return y
    end
end

function supdist(dx, dy)
    return max(abs(dx), abs(dy))
end

function adjacent(dx, dy)
    return abs(dx) <= 1 and abs(dy) <= 1
end
