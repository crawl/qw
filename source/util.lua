--------------------
-- Utility functions

function enum(tbl)
    local e = {}
    for i = 0, #tbl - 1 do
        e[tbl[i + 1]] = i
    end

    return e
end

function enum_string(val, tbl)
    for k, v in pairs(tbl) do
        if v == val then
            return k
        end
    end
end

function contains_string_in(name, t)
    for _, value in ipairs(t) do
        if name:find(value) then
            return true
        end
    end
    return false
end

function split(str, del)
    local res = {}
    local v
    for v in str:gmatch("([^" .. del .. "]+)") do
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

function sign(a)
    return a > 0 and 1 or a < 0 and -1 or 0
end

function abs(a)
    return a * sign(a)
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

function table_is_empty(t)
    local empty = true
    for _, v in pairs(t) do
        empty = false
        break
    end
    return empty
end
