function get_feature_name(where_name)
    for _, value in ipairs(portal_data) do
        if where_name == value[1] then
            return value[3]
        end
    end
end

function feature_is_traversable(feat)
    return feat ~= "unseen"
        and (open_runed_doors or not feature_is_runed_door(feat))
        and travel.feature_traversable(feat)
end

function is_traversable_at(pos)
    return feature_is_traversable(view.feature_at(pos.x, pos.y))
end

function is_cornerish_at(pos)
    if is_traversable_at({ x = pos.x + 1, y = pos.y + 1 })
            or is_traversable_at({ x = pos.x + 1, y = pos.y - 1 })
            or is_traversable_at({ x = pos.x - 1, y = pos.y + 1 })
            or is_traversable_at({ x = pos.x - 1, y = pos.y - 1 }) then
        return false
    end
    return (is_traversable_at({ x = pos.x + 1, y = y })
            or is_traversable_at({ x = pos.x - 1, y = y }))
        and (is_traversable_at({ x = pos.x, y = pos.y + 1 })
            or is_traversable_at({ x = pos.x, y = pos.y - 1 }))
end

function is_solid_at(pos)
    local feat = view.feature_at(pos.x, pos.y)
    return feat == "unseen" or travel.feature_solid(feat)
end

function destroys_items_at(pos)
    return feat == "deep_water" and not intrinsic_amphibious()
        or feat == "lava"
end

function feature_is_upstairs(feat)
    return feat:find("stone_stairs_up")
        or feat:find("^exit_") and not feat == "exit_dungeon"
end

function feature_is_runed_door(feat)
    return feat == "runed_clear_door" or feat == "runed_door"
end

function feature_uses_map_key(key, feat)
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

function feature_is_critical(feat)
    return feature_uses_map_key(">", feat)
        or feature_uses_map_key("<", feat)
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

function feature_is_upstairs(feat)
    return feat:find("stone_stairs_up")
        or feat:find("^exit_") and not feat == "exit_dungeon"
end

function cloud_is_dangerous(cloud)
    if cloud == "flame" or cloud == "fire" then
        return (you.res_fire() < 1)
    elseif cloud == "noxious fumes" then
        return (not meph_immune())
    elseif cloud == "freezing vapour" then
        return (you.res_cold() < 1)
    elseif cloud == "poison gas" then
        return (you.res_poison() < 1)
    elseif cloud == "calcifying dust" then
        return (you.race() ~= "Gargoyle")
    elseif cloud == "foul pestilence" then
        return (not miasma_immune())
    elseif cloud == "seething chaos" or cloud == "mutagenic fog" then
        return true
    end
    return false
end
