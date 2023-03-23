--------------------
-- Utility functions

function enum(tbl)
    local e = {}
    for i = 0, #tbl - 1 do
        e[tbl[i + 1]] = i
    end

    return e
end

function contains_string_in(name, t)
    for _, value in ipairs(t) do
        if string.find(name, value) then
            return true
        end
    end
    return false
end

function split(str, del)
    local res = {}
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
    -- We do this to avoid returning multiple results from string.gsub().
    local result = str:gsub("^%s+", ""):gsub("%s+$", "")
    return result
end

function control(c)
    return string.char(string.byte(c) - string.byte('a') + 1)
end

local a2c = { ['u'] = -254, ['d'] = -253, ['l'] = -252 ,['r'] = -251 }
function arrowkey(c)
    return a2c[c]
end

local d2v = {
    [-1] = { [-1] = 'y', [0] = 'h', [1] = 'b' },
    [0]  = { [-1] = 'k', [1] = 'j' },
    [1]  = { [-1] = 'u', [0] = 'l', [1] = 'n' },
}
local v2d = {}
for x, _ in pairs(d2v) do
    for y, c in pairs(d2v[x]) do
        v2d[c] = { x = x, y = y }
    end
end

function delta_to_vi(pos)
    return d2v[pos.x][pos.y]
end

function vi_to_delta(c)
    return v2d[c]
end

function sign(a)
    return a > 0 and 1 or a < 0 and -1 or 0
end

function abs(a)
    return a * sign(a)
end

function vector_move(pos)
    local str = ''
    for i = 1, abs(pos.x) do
        str = str .. delta_to_vi({ x = sign(pos.x), y = 0 })
    end
    for i = 1, abs(pos.y) do
        str = str .. delta_to_vi({ x = 0, y = sign(pos.y) })
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

function supdist(pos)
    return max(abs(pos.x), abs(pos.y))
end

function is_adjacent(pos)
    return abs(pos.x) <= 1 and abs(pos.y) <= 1
end

function pos_string(pos)
    return tostring(pos.x) .. ", " .. tostring(pos.y)
end
