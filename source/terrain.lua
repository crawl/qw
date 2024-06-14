------------------
-- Terrain data and functions.

-- Feature exploration state enum
const.explore = {
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

function cloud_is_safe(cloud)
    if not cloud then
        return true
    end

    if cloud == "flame"
            or cloud == "freezing vapour"
            or cloud == "thunder"
            or cloud == "acidic fog"
            or cloud == "seething chaos"
            or cloud == "mutagenic fog" then
        return false
    end

    if cloud == "steam" then
        return you.res_fire() > 0
    elseif cloud == "noxious fumes" then
        return meph_immune()
    elseif cloud == "poison gas" then
        return you.res_poison() > 0
    elseif cloud == "foul pestilence" then
        return miasma_immune()
    elseif cloud == "calcifying dust" then
        return you.race() == "Gargoyle" or you.transform() == "statue"
    elseif cloud == "excruciating misery" then
        return intrinsic_undead()
    end

    return true
end

function cloud_is_dangerous_at(pos)
    local cloud = view.cloud_at(pos.x, pos.y)
    if not cloud then
        return false
    end

    -- We require full safety if no monsters are around.
    if not qw.danger_in_los then
        return not cloud_is_safe(cloud)
    end

    -- We'll still take damage from these with a level of resistance, but
    -- don't consider that dangerous.
    if cloud == "flame" then
        return you.res_fire() < 1
    elseif cloud == "freezing vapour" then
        return you.res_cold() < 1
    elseif cloud == "thunder" then
        return you.res_shock() < 1
    end

    return not cloud_is_safe(cloud)
end

-- Hook to determine which traps are safe to move over without requiring an
-- answer to a yesno prompt. This can be conditionally disabled with
-- qw.ignore_traps, e.g. as we do on Zot:5.
--
-- XXX: We have to mark Zot traps as safe so we don't get the prompt, as
-- c_answer_prompt isn't called in that case. Should have the crawl
-- yes_or_no() function call c_answer_prompt to fix this.
function c_trap_is_safe(trap)
    if not trap then
        return true
    end

    trap = trap:lower()
    return qw.ignore_traps
        or trap == "zot"
        or you.race() == "Formicid"
            and (trap == "permanent teleport" or trap == "dispersal")
end

function trap_is_safe_at(pos)
    -- A trap is always safe if we're already standing on it.
    if positions_equal(pos, const.origin) then
        return true
    end

    local feat = view.feature_at(pos.x, pos.y)
    if not feat:find("^trap_") then
        return true
    end

    local trap = feat:gsub("trap_", "")
    return c_trap_is_safe(trap) and trap ~= "zot"
end

function is_safe_at(pos, assume_flight)
    local map_pos = position_sum(qw.map_pos, pos)
    if not map_is_unexcluded_at(map_pos) then
        return false
    end

    if assume_flight then
        local feat = view.feature_at(pos.x, pos.y)
        if not feature_is_traversable(feat, true) then
            return false
        end
    elseif not map_is_traversable_at(map_pos) then
        return false
    end

    local cloud = view.cloud_at(pos.x, pos.y)
    if not cloud_is_safe(cloud) then
        return false
    end

    return trap_is_safe_at(pos)
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
