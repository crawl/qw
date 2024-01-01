------------------
-- Terrain data and functions.

-- Feature state enum
const.feat_state = {
    "none",
    "seen",
    "diggable",
    "reachable",
    "explored",
}

function get_feature_name(where_name)
    for _, value in ipairs(portal_data) do
        if where_name == value[1] then
            return value[3]
        end
    end
end

function feature_is_traversable(feat, assume_flight)
    -- XXX: Can we pass a default nil value instead?
    return travel.feature_traversable(feat, assume_flight and true or false)
                and not feature_is_runed_door(feat)
            or feat:find("^trap") ~= nil
end

function feature_is_diggable(feat)
    return feat == "rock_wall"
        or feat == "clear_rock_wall"
        or feat == "slimy_wall"
        or feat == "iron_grate"
        or feat == "granite_statue"
end

function is_safe_at(pos, assume_flight)
    return view.is_safe_square(pos.x, pos.y, assume_flight)
        and view.feature_at(pos.x, pos.y) ~= "trap_zot"
end

function is_cloud_safe_at(pos, is_safe, assume_flight)
    if is_safe == nil then
        is_safe = is_safe_at(pos, assume_flight)
    end

    if is_safe then
        return true
    end

    local cloud = view.cloud_at(pos.x, pos.y)
    return not cloud or qw.danger_in_los and not cloud_is_dangerous(cloud)
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

function count_adjacent_slimy_walls_at(pos)
    -- No need to count if we've never spotted a wall on the level during a map update.
    if not qw.have_slimy_walls then
        return 0
    end

    local count = 0
    for apos in adjacent_iter(pos) do
        if view.feature_at(apos.x, apos.y) == "slimy_wall" then
            count = count + 1
        end
    end
    return count
end

function is_solid_at(pos, exclude_doors)
    local feat = view.feature_at(pos.x, pos.y)
    return (feat == "unseen" or travel.feature_solid(feat))
        and (not exclude_doors
            or feat ~= "closed_door" and feat ~= "closed_clear_door")
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
        return dir and dir == const.dir.down
            or feat == "transporter"
            or feat == "escape_hatch_down"
    elseif key == "<" then
        return dir and dir == const.dir.up
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
        dir = const.dir.down
    elseif feat:find("^stone_stairs_up") then
        dir = const.dir.up
    else
        return
    end

    local num = feat:gsub("stone_stairs_"
        .. (dir == const.dir.down and "down_" or "up_"), "", 1)
    return dir, num
end

function branch_stairs_type(feat)
    local dir
    if feat:find("^enter_") then
        dir = const.dir.down
    elseif feat:find("^exit_") then
        dir = const.dir.up
    else
        return
    end

    if feat == branch_exit("D") then
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
        return const.dir.up
    elseif feat == "escape_hatch_down" then
        return const.dir.down
    end
end

function cloud_is_dangerous(cloud)
    if cloud == "flame" or cloud == "fire" then
        return you.res_fire() < 1
    elseif cloud == "noxious fumes" then
        return not meph_immune()
    elseif cloud == "freezing vapour" then
        return you.res_cold() < 1
    elseif cloud == "poison gas" then
        return you.res_poison() < 1
    elseif cloud == "calcifying dust" then
        return you.race() ~= "Gargoyle"
    elseif cloud == "foul pestilence" then
        return not miasma_immune()
    elseif cloud == "seething chaos" or cloud == "mutagenic fog" then
        return true
    end
    return false
end

function update_runelight(hash, state, force)
    if state.safe == nil and not state.feat then
        error("Undefined runelight state.")
    end

    if not c_persist.runelights[hash] then
        c_persist.runelights[hash] = {}
    end

    local current = c_persist.runelights[hash]
    if current.safe == nil then
        current.safe = true
    end
    if current.feat == nil then
        current.feat = const.feat_state.none
    end

    if state.safe == nil then
        state.safe = current.safe
    end

    if state.feat == nil then
        state.feat = current.feat
    end

    local feat_state_changed = current.feat < state.feat
            or force and current.feat ~= state.feat
    if state.safe ~= current.safe or feat_state_changed then
        if debug_channel("explore") then
            dsay("Updating runelight at "
                .. los_pos_string(unhash_position(hash)) .. " from "
                .. stairs_state_string(current) .. " to "
                .. stairs_state_string(state))
        end

        current.safe = state.safe

        if feat_state_changed then
            current.feat = state.feat
        end
    end
end

-- Hook to determine which traps are safe to move over without requiring an
-- answer to a yesno prompt. This can be conditionally disabled with
-- ignore_traps, e.g. as we do on Zot:5.
--
-- XXX: We have to mark Zot traps as safe so we don't get the prompt, as
-- c_answer_prompt isn't called in that case. Should have the crawl
-- yes_or_no() function call c_answer_prompt to fix this.
function c_trap_is_safe(trap)
    return ignore_traps
        or trap == "Zot"
        or you.race() == "Formicid"
            and (trap == "permanent teleport" or trap == "dispersal")
end
