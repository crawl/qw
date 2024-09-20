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

function capitalise(str)
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
    for _, v in pairs(t) do
        return false
    end

    return true
end

function empty_string(s)
    return not s or s == ''
end

function bool_to_number(x)
    if x == true then
        return 1
    elseif x == false then
        return 0
    else
        return x
    end
end

--[[
Compare the values of tables numerically for the given keys. The keys are
compared in the order given in `keys`, with the comparison moving to the next
key when there's a tie with the current key. If either table has a nil value
for a given key, their values for that key are considered tied. Boolean values
are converted to 1 for true and 0 for false. All other values types are
invalid.
@table a             A table to compare.
@table b             A table to compare.
@table keys          A list of keys to compare values in tables a and b.
@table reversed_keys A table of keys set to true for a key where the values
                     should be compared in reverse.
@treturn boolean True if, for some key k in the given key order, a has a better
                 value than b for k, and for all keys before k, a and b are
                 either equal or one of the two tables has a nil value. False
                 otherwise.
--]]
function compare_table_keys(a, b, keys, reversed_keys)
    for _, key in ipairs(keys) do
        local val1 = a[key]
        local val2 = b[key]
        if val1 ~= nil and val2 ~= nil then
            val1 = bool_to_number(val1)
            val2 = bool_to_number(val2)

            local greater_val = not (reversed_keys and reversed_keys[key])
            if val1 > val2 then
                return greater_val
            elseif val1 < val2 then
                return not greater_val
            end
        end
    end
    return false
end
