function get_feat_name(where_name)
    for _, value in ipairs(portal_data) do
        if where_name == value[1] then
            return value[3]
        end
    end
end

function is_traversable(x, y)
    local feat = view.feature_at(x, y)
    return feat ~= "unseen" and travel.feature_traversable(feat)
end

function is_cornerish(x, y)
    if is_traversable(x+ 1, y + 1)
            or is_traversable(x + 1, y - 1)
            or is_traversable(x - 1, y + 1)
            or is_traversable(x - 1, y - 1) then
        return false
    end
    return (is_traversable(x + 1, y) or is_traversable(x - 1, y))
        and (is_traversable(x, y + 1) or is_traversable(x, y - 1))
end

function is_solid(x, y)
    local feat = view.feature_at(x, y)
    return feat == "unseen" or travel.feature_solid(feat)
end

function feat_is_deep_water_or_lava(feat)
    return feat == "deep_water" or feat == "lava"
end

function deep_water_or_lava(x, y)
    return feat_is_deep_water_or_lava(view.feature_at(x, y))
end

function feat_is_upstairs(feat)
    return feat:find("stone_stairs_up")
        or feat:find("^exit_") and not feat == "exit_dungeon"
end

function feat_uses_map_key(key, feat)
    if key == ">" then
        return feat:find("stone_stairs_down")
            or feat:find("enter_")
            or feat == "transporter"
            or feat == "escape_hatch_down"
    elseif key == "<" then
        return feat:find("stone_stairs_up")
            or feat:find("exit_")
            or feat == "escape_hatch_up"
    else
        return false
    end
end

function feat_is_critical(feat)
    return feat_uses_map_key(">", feat)
        or feat_uses_map_key("<", feat)
        or feat:find("shop")
        or feat:find("altar")
        or feat:find("transporter")
        or feat:find("transit")
        or feat:find("abyss")
end

function stone_stair_type(feat)
    local dir
    if feat:find("stone_stairs_down") then
        dir = DIR.DOWN
    elseif feat:find("stone_stairs_up") then
        dir = DIR.UP
    else
        return
    end

    return dir, feat:gsub("stone_stairs_"
        .. (dir == DIR.DOWN and "down_" or "up_"), "")
end

function feat_is_upstairs(feat)
    return feat:find("stone_stairs_up")
        or feat:find("^exit_") and not feat == "exit_dungeon"
end
