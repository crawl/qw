function get_feature_name(where_name)
    for _, value in ipairs(portal_data) do
        if where_name == value[1] then
            return value[3]
        end
    end
end

function feature_is_traversable(feat, assume_flight)
    return (open_runed_doors or not feature_is_runed_door(feat))
        -- XXX: Can we pass a default nil value instead?
        and travel.feature_traversable(feat, assume_flight and true or false)
end

function is_cornerish_at(pos)
    if is_traversable_at({ x = pos.x + 1, y = pos.y + 1 })
            or is_traversable_at({ x = pos.x + 1, y = pos.y - 1 })
            or is_traversable_at({ x = pos.x - 1, y = pos.y + 1 })
            or is_traversable_at({ x = pos.x - 1, y = pos.y - 1 }) then
        return false
    end

    return (is_traversable_at({ x = pos.x + 1, y = pos.y })
            or is_traversable_at({ x = pos.x - 1, y = pos.y }))
        and (is_traversable_at({ x = pos.x, y = pos.y + 1 })
            or is_traversable_at({ x = pos.x, y = pos.y - 1 }))
end

function is_solid_at(pos)
    local feat = view.feature_at(pos.x, pos.y)
    return feat == "unseen" or travel.feature_solid(feat)
end

function feature_destroys_items(feat)
    return feat == "deep_water" and not intrinsic_amphibious()
        or feat == "lava"
end

function destroys_items_at(pos)
    return feature_destroys_items(view.feature_at(pos.x, pos.y))
end

function feature_is_upstairs(feat)
    return feat:find("^stone_stairs_up") or feat:find("^exit_")
end

function feature_is_downstairs(feat)
    return feat:find("^stone_stairs_down")
end

function feature_is_runed_door(feat)
    return feat == "runed_clear_door" or feat == "runed_door"
end

function feature_uses_map_key(key, feat)
    local dir = stone_stairs_type(feat)
    if not dir then
        dir = select(2, branch_stairs_type(feat))
    end

    if key == ">" then
        return dir and dir == DIR.DOWN
            or feat == "transporter"
            or feat == "escape_hatch_down"
    elseif key == "<" then
        return dir and dir == DIR.UP
            or feat == "escape_hatch_up"
    else
        return false
    end
end

function feature_is_critical(feat)
    return feature_uses_map_key(">", feat)
        or feature_uses_map_key("<", feat)
        or feat:find("_shop")
        or feat:find("altar_")
        or feat:find("transporter")
        or feat:find("transit")
        or feat:find("abyss")
end

function stone_stairs_type(feat)
    local dir
    if feat:find("^stone_stairs_down") then
        dir = DIR.DOWN
    elseif feat:find("^stone_stairs_up") then
        dir = DIR.UP
    else
        return
    end

    local num = feat:gsub("stone_stairs_"
        .. (dir == DIR.DOWN and "down_" or "up_"), "", 1)
    return dir, num
end

function branch_stairs_type(feat)
    local dir
    if feat:find("^enter_") then
        dir = DIR.DOWN
    elseif feat:find("^exit_") then
        dir = DIR.UP
    else
        return
    end

    if feat == "exit_dungeon" then
        return "D", dir
    end

    local entry_feat = feat:gsub("exit", "enter", 1)
    for branch, entry in pairs(branch_data) do
        if entry.entrance == entry_feat then
            return branch, dir
        end
    end
end

function escape_hatch_type(feat)
    if feat == "escape_hatch_up" then
        return DIR.UP
    elseif feat == "escape_hatch_down" then
        return DIR.DOWN
    end
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

function update_runelight(hash, state, force)
    if state.safe == nil and not state.los then
        error("Undefined runelight state.")
    end

    if not c_persist.runelights[hash] then
        c_persist.runelights[hash] = {}
    end

    local current = c_persist.runelights[hash]
    if current.safe == nil then
        current.safe = true
    end
    if current.los == nil then
        current.los = FEAT_LOS.NONE
    end

    if state.safe == nil then
        state.safe = current.safe
    end

    if state.los == nil then
        state.los = current.los
    end

    local los_changed = current.los < state.los
            or force and current.los ~= state.los
    if state.safe ~= current.safe or los_changed then
        if debug_channel("explore") then
            local pos = position_difference(unhash_position(hash), global_pos)
            dsay("Updating Abyss runelight at " .. pos_string(pos) .. " from "
                .. stairs_state_string(current) .. " to "
                .. stairs_state_string(state))
        end

        current.safe = state.safe

        if los_changed and not force then
            current.los = state.los
        end
    end
end

function get_map_runelight(pos)
    local hash = hash_position(pos)
    return c_persist.runelights[hash]
end
