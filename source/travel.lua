------------------
-- Travel planning

-- Go up from branch, tracking parent branches and their entries to the child
-- branches we came from.
function parent_branch_chain(branch, check_branch, check_entries)
    if branch == "D" then
        return
    end

    local parents = {}
    local entries = {}
    local cur_branch = branch
    local stop_search = false
    while cur_branch ~= "D" and not stop_search do
        local parent, min_depth = parent_branch(cur_branch)

        if check_branch == parent
                or check_entries and check_entries[parent] then
            stop_search = true
        end

        -- Travel into the branch assuming we enter from min_depth. If this
        -- ends up being our stopping point because we haven't found the
        -- branch, this will be handled later in update_goal_travel().
        entries[parent] = min_depth
        table.insert(parents, parent)
        cur_branch = parent
    end

    return parents, entries
end

function travel_branch_levels(result, dest_depth)
    local dir = sign(dest_depth - result.depth)
    if dir ~= 0 and not result.first_dir and not result.first_branch then
        result.first_dir = dir
    end

    while result.depth ~= dest_depth do
        if count_stairs(result.branch, result.depth, dir,
                const.explore.seen) == 0 then
            return
        end

        result.depth = result.depth + dir
    end
end

function travel_up_branches(result, parents, entries, dest_branch)
    if not result.first_dir and not result.first_branch then
        result.first_dir = const.dir.up
    end

    local i = 1
    for i = 1, #parents do
        if result.branch == dest_branch then
            return
        end

        if is_hell_branch(result.branch) then
            if not branch_found(result.branch, const.explore.reachable)
                    or parents[i] ~= parent_branch(result.branch) then
                return
            end
        else
            travel_branch_levels(result, 1)
            if result.depth ~= 1 then
                return
            end
        end

        result.branch = parents[i]
        result.depth = entries[result.branch]
    end
end

function travel_down_branches(result, dest_branch, dest_depth, parents,
        entries)
    local i = #parents
    for i = #parents, 1, -1 do
        result.branch = parents[i]
        result.depth = entries[result.branch]

        local next_branch, next_depth
        if i > 1 then
            next_branch = parents[i - 1]
            next_depth = entries[next_branch]
        else
            next_branch = dest_branch
            next_depth = dest_depth
        end

        if not result.first_dir and not result.first_branch then
            result.first_branch = next_branch
        end

        -- We stop if we haven't found the next branch or if we can't actually
        -- enter it with travel.
        if not branch_found(next_branch, const.explore.reachable)
                or not branch_travel(next_branch) then
            result.stop_branch = next_branch
            break
        end

        result.branch = next_branch
        result.depth = 1

        travel_branch_levels(result, next_depth)
        if result.depth ~= next_depth then
            break
        end

        i = i - 1
    end
end

--[[
Search branch and stair data from a starting level to a destination level,
returning the furthest point to which we know we can travel.
@string  start_branch The starting branch. Defaults to the current branch.
@int     start_depth  The starting depth. Defaults to the current depth.
@string  dest_branch  The destination branch.
@int     dest_depth   The destination depth.
@treturn table        The travel search results. A table that always
                      contains keys 'branch' and 'depth' containing the
                      furthest level reached. If a 'stairs_dir' key is
                      present, we should do a map mode stairs search to take
                      unexplored stairs in the given direction. If the
                      travel destination is not the current level, the table
                      will have either a key of 'first_dir' indicating the
                      first stair direction we should take during travel, or
                      a key of 'first_branch' indicating that we should
                      first proceed into the given branch. These two values
                      are used by movement plans when we're stuck.
--]]
function travel_destination_search(dest_branch, dest_depth, start_branch,
        start_depth)
    if not start_branch then
        start_branch = where_branch
    end
    if not start_depth then
        start_depth = where_depth
    end
    local result = { branch = start_branch, depth = start_depth }

    -- We're already there.
    if start_branch == dest_branch and start_depth == dest_depth then
        return result
    end

    local common_parent, start_parents, start_entries, dest_parents,
        dest_entries
    if start_branch == dest_branch
            and not (is_hell_branch(start_branch)
                and start_depth > dest_depth) then
        common_parent = start_branch
    else
        start_parents, start_entries = parent_branch_chain(start_branch,
            dest_branch)
        dest_parents, dest_entries = parent_branch_chain(dest_branch,
            start_branch, start_entries)
        if dest_parents then
            common_parent = dest_parents[#dest_parents]
        else
            common_parent = "D"
        end
    end

    -- Travel up and out of the starting branch until we reach the common
    -- parent branch. Don't bother traveling up if the destination branch is a
    -- sub-branch of the starting branch.
    if start_branch ~= common_parent then
        travel_up_branches(result, start_parents, start_entries, common_parent)

        -- We weren't able to travel all the way up to the common parent.
        if result.depth ~= start_entries[common_parent] then
            return result
        end
    end

    -- We've already arrived at our ultimate destination.
    if result.branch == dest_branch and result.depth == dest_depth then
        return result
    end

    -- We're now in the nearest branch in the chain of parent branches of our
    -- starting branch that is also in the chain of parent branches containing
    -- the destination branch. Travel in this nearest branch to the depth of
    -- the first branch entry we'll need to take to start descending to our
    -- destination.
    local next_depth
    if common_parent == dest_branch then
        next_depth = dest_depth
    else
        next_depth = dest_entries[common_parent]
    end
    travel_branch_levels(result, next_depth)

    -- We couldn't make it to the branch entry we need or we already arrived at
    -- our ultimate destination.
    if result.depth ~= next_depth
            or result.branch == dest_branch and result.depth == dest_depth then
        return result
    end

    -- Travel into and down branches to reach our ultimate destination. We're
    -- always starting at the first branch entry we'll need to take.
    travel_down_branches(result, dest_branch, dest_depth, dest_parents,
        dest_entries)
    return result
end

function travel_opens_runed_doors(result)
    if result.stop_branch == "Pan"
                and not branch_found("Pan", const.explore.reachable)
            or result.stop_branch == "Slime"
                and branch_found("Slime")
                and not branch_found("Slime", const.explore.reachable) then
        local parent, min_depth, max_depth = parent_branch(result.stop_branch)
        local level = make_level(result.branch, result.depth)
        return result.branch == parent
            and result.depth >= min_depth
            and result.depth <= max_depth
    end

    return false
end

function travel_safe_stairs(result)
    -- We only consider taking stair safety when taking downstairs or branch
    -- entries. Taking alternate upstairs would be far less useful generally,
    -- and fleeing doesn't yet support fleeing to downstairs, which would be
    -- necessary before we could take alternate upstairs.
    if qw.safe_stairs_failed
            or result.stairs_dir
            or where_branch == result.branch
                and where_depth >= result.depth then
        return
    end

    local best_stairs, best_threat, best_safe, worst_threat
    local stairs = level_stairs_features(result.branch, result.depth, const.dir.up)
    local level = make_level(result.branch, result.depth)
    for _, feat in ipairs(stairs) do
        -- If the stairs are unknown, assume a threat of 0.
        local state = get_stairs(result.branch, result.depth, feat)
        local threat = 0
        -- Unknown stairs are safe.
        local safe = true
        if state then
            threat = state.threat
            safe = state.safe
        -- We're arriving to the Vaults:$ ambush, which is guaranteed to have
        -- 25 vaults guards.
        elseif level == vaults_end then
            threat = 25
        -- We prefer taking stairs that have a known but low threat over taking
        -- unknown ones. So assume unknown stairs have high threat.
        else
            threat = high_threat_level()
        end

        if not worst_threat or threat > worst_threat then
            worst_threat = threat
        end

        local dest_feat = feat
        if result.depth > 1 then
            dest_feat = dest_feat:gsub("_up_", "_down_", 1)
        else
            dest_feat = branch_entrance(result.branch)
        end
        local dest_state = get_destination_stairs(result.branch, result.depth, feat)
        safe = safe and dest_state and dest_state.safe
        if (not best_safe or safe)
                and (not best_threat or threat < best_threat) then
            best_stairs = dest_feat
            best_threat = threat
            best_safe = safe
        end
    end

    -- If no stair has enough threat that we need to buff, we don't need to
    -- take safe stairs.
    if worst_threat < high_threat_level()
            -- If all stairs have equally bad threat and we don't need to
            -- teleport, don't use safe stairs. This will most commonly happen
            -- when all stairs at the destination are unknown.
            or (best_threat == worst_threat
                and best_threat < extreme_threat_level()) then
        return
    end

    -- If the best destination stair threat is high enough, we try to use down
    -- hatches to reach the level.
    local hatches, best_hash
    if best_threat >= extreme_threat_level() and result.depth > 1 then
        local prev_level = make_level(result.branch, result.depth - 1)
        hatches = c_persist.down_hatches[prev_level]
    end
    if hatches then
        for hash, state in pairs(hatches) do
            if not best_safe or state.safe then
                best_hash = hash
                best_safe = state.safe

                -- Stop if we find a safe hatch.
                if best_safe then
                    break
                end
            end
        end
    end

    if best_hash then
        result.safe_hatch = best_hash
    elseif best_stairs then
        result.safe_stairs = best_stairs
    else
        return
    end

    result.depth = result.depth - 1
end

function finalize_first_dir(result)
    if where_branch == result.branch then
        if where_depth == result.depth then
            result.first_dir = nil
        else
            result.first_dir = sign(result.depth - where_depth)
        end
    end
end

function finalize_depth_dir(result, dir)
    assert(type(dir) == "number" and abs(dir) == 1,
        "Invalid stair direction: " .. tostring(dir))

    -- We can already reach all required stairs in the given direction on the
    -- target level, so there's nothing to do in that direction.
    if count_stairs(result.branch, result.depth, dir,
                const.explore.reachable)
            == num_required_stairs(result.branch, depth, dir) then
        return false
    end

    local dir_depth = result.depth + dir
    local dir_depth_stairs = count_stairs(result.branch, dir_depth, -dir,
            const.explore.explored)
        < count_stairs(result.branch, dir_depth, -dir,
            const.explore.reachable)
    -- The level in the given direction isn't autoexplored, so we start there.
    if not autoexplored_level(result.branch, dir_depth) then
        result.depth = dir_depth

        -- If we haven't fully explored explored this level but we already see
        -- there are unexplored stairs, take those before finishing
        -- autoexplore.
        if dir_depth_stairs then
            result.stairs_dir = -dir
        end

        finalize_first_dir(result)
        return true
    end

    -- Both the target level and the level in the given direction are
    -- autoexplored, so we try any unexplored stairs on the target level in
    -- that direction.
    if count_stairs(result.branch, result.depth, dir,
                const.explore.explored)
            < count_stairs(result.branch, result.depth, dir,
                const.explore.reachable) then
        result.stairs_dir = dir
        return true
    end

    -- No unexplored stairs in the given direction on our target level, but on
    -- the level in that direction we have some stairs in the opposite
    -- direction, so we try those.
    if dir_depth_stairs then
        result.depth = dir_depth
        result.stairs_dir = -dir

        finalize_first_dir(result)

        return true
    end

    return false
end

-- Try to get a "final" depth and any needed stair search direction.
function finalize_travel_depth(result)
    if travel_opens_runed_doors(result) then
        result.open_runed_doors = true
        return
    end

    if not autoexplored_level(result.branch, result.depth) then
        return
    end

    -- If we can go up a level within our current branch, finalize depth and
    -- direction in that direction.
    local up_reachable = result.depth > 1
        and count_stairs(result.branch, result.depth, const.dir.up,
            const.explore.reachable) > 0
    local finished
    if up_reachable then
        if finalize_depth_dir(result, const.dir.up) then
            return
        end
    end

    -- If up is not reachable or we didn't finalize in that direction, try to
    -- finalize down.
    local down_reachable = result.depth < branch_depth(result.branch)
        and count_stairs(result.branch, result.depth, const.dir.down,
            const.explore.reachable) > 0
    if down_reachable and finalize_depth_dir(result, const.dir.down) then
        return
    end

    -- We're not successfully finalized, so we'll attempt resets of stair
    -- states for stairs going up and stairs on the level above going down.
    local finished
    if up_reachable
            -- Don't reset up stairs if we still need the branch rune, since we
            -- have specific plans for branch ends we may need to follow.
            and (have_branch_runes(result.branch)
                or result.depth < branch_rune_depth(result.branch)) then
        reset_stone_stairs(result.branch, result.depth, const.dir.up)
        reset_stone_stairs(result.branch, result.depth - 1, const.dir.down)
        result.depth = result.depth - 1
        finalize_first_dir(result)
        result.stairs_dir = const.dir.down
        finished = true
    end

    if down_reachable then
        reset_stone_stairs(result.branch, result.depth, const.dir.down)
        reset_stone_stairs(result.branch, result.depth + 1, const.dir.up)
        -- If we've just reset upstairs, that direction gets priority as the
        -- first search destination.
        if not finished then
            result.depth = result.depth + 1
            finalize_first_dir(result)
            result.stairs_dir = const.dir.up
        end
    end
end

function travel_destination(dest_branch, dest_depth, finalize_dest)
    if not dest_branch or in_portal() then
        return {}
    end

    local result = travel_destination_search(dest_branch, dest_depth)
    -- We were unable enter the branch in result.stop_branch, so figure out the
    -- next best travel location in the branch's parent.
    if result.stop_branch
            and not branch_found(result.stop_branch, const.explore.reachable) then
        local parent, min_depth, max_depth = parent_branch(result.stop_branch)
        result.branch = parent
        result.depth = next_exploration_depth(parent, min_depth, max_depth)
        if not result.depth then
            result.depth = min_depth
        end
    end

    -- Get the final depth to which we should actually travel given the state
    -- of exploration at our travel destination. Some searches never finalize
    -- at their destination because they are for a known objective on the
    -- destination level.
    if finalize_dest
            or result.branch ~= dest_branch
            or result.depth ~= dest_depth then
        finalize_travel_depth(result)
    end

    travel_safe_stairs(result)

    return result
end

function update_goal_travel()
    if goal_status == "Save" or goal_status == "Quit" then
        goal_travel = {}
        return
    end

    -- We use a stash search to reach our destination, but will still do a
    -- travel search for any given goal branch/depth, so we can use a go
    -- command as a backup.
    local want_stash = goal_status == "Orb" and c_persist.found_orb
        or not goal_branch
        or goal_status:find("^God") and goal_branch ~= "Temple"
        or is_portal_branch(goal_branch)
            and not in_portal()
            and branch_found(goal_branch, const.explore.reachable)
        or goal_branch == "Abyss"
            and not in_branch("Abyss")
            and branch_found("Abyss", const.explore.reachable)
        or goal_branch == "Pan"
            and not in_branch("Pan")
            and branch_found("Pan", const.explore.reachable)

    goal_travel = travel_destination(goal_branch, goal_depth,
        not want_stash and goal_status ~= "Escape")

    if goal_status == "Escape" and where == "D:1" then
        goal_travel.first_dir = const.dir.up
    end

    goal_travel.want_stash = want_stash
    goal_travel.want_go = not in_branch("Abyss")
        -- We always try to GD0 when escaping.
        and (goal_status == "Escape"
            or goal_travel.branch
                and (where_branch ~= goal_travel.branch
                    or where_depth ~= goal_travel.depth))

    local goal_reachable = true
    local goal_feats = goal_travel_features()
    local goal_positions
    if goal_feats then
        goal_positions = get_feature_map_positions(goal_feats)
        goal_reachable = false
    end

    if goal_positions then
        for _, pos in ipairs(goal_positions) do
            if map_is_reachable_at(pos) then
                goal_reachable = true
                break
            end
        end
    end

    -- Don't autoexplore if we want to travel in some way. This allows us to
    -- leave the level before it's completely explored.
    disable_autoexplore = (goal_travel.stairs_dir
            or goal_travel.safe_stairs
            or goal_travel.safe_hatch
            or goal_travel.want_go
            or goal_travel.want_stash)
        and goal_reachable
        -- We do allow autoexplore even when we want to travel if the current
        -- is fully explored, since then it's safe to pick up any surrounding
        -- items like thrown projectiles or loot from e.g. stairdancing.
        and (not explored_level(where_branch, where_depth)
        -- However we don't allow autoexplore in this case if we're in the
        -- Abyss, we're escaping with the Orb, or our current level is our
        -- travel destination. The last exception is to allow within-level
        -- plans like taking unexplored stairs and stash searches to on-level
        -- destinations like altars to not be interrupted when runed doors
        -- exist. In that case autoexplore would move us next to a runed door
        -- and off of our intermediate stair, altar, etc., where we need to be.
            or (in_branch("Abyss")
                or goal_status == "Escape" and qw.have_orb
                or goal_travel.branch and not goal_travel.want_go))

    if debug_channel("goals") then
        if goal_travel.branch then
            dsay("Travel destination: "
                .. make_level(goal_travel.branch, goal_travel.depth))
        end

        if goal_travel.stairs_dir then
            dsay("Stairs search dir: " .. tostring(goal_travel.stairs_dir))
        elseif goal_travel.safe_stairs then
            dsay("Taking specific stairs for safety: "
                .. goal_travel.safe_stairs)
        elseif goal_travel.safe_hatch then
            dsay("Taking hatch on destination level for safety at "
                .. pos_string(unhash_position(goal_travel.safe_hatch)))
        end

        if goal_travel.first_dir then
            dsay("First dir: " .. tostring(goal_travel.first_dir))
        elseif goal_travel.first_branch then
            dsay("First branch: " .. tostring(goal_travel.first_branch))
        end

        dsay("Want stash travel: " .. bool_string(goal_travel.want_stash))
        dsay("Want go travel: " .. bool_string(goal_travel.want_go))
        dsay("Disable autoexplore: " .. bool_string(disable_autoexplore))
    end
end

function goal_travel_features()
    local on_travel_level = goal_travel.branch == where_branch
        and goal_travel.depth == where_depth
    if goal_travel.stairs_dir and on_travel_level then
        local feats = level_stairs_features(where_branch, where_depth,
            goal_travel.stairs_dir)
        local wanted_feats = {}
        for _, feat in ipairs(feats) do
            local state = get_stairs(where_branch, where_depth, feat)
            if not state or state.feat < const.explore.explored then
                table.insert(wanted_feats, feat)
            end
        end
        if #wanted_feats > 0 then
            return wanted_feats
        end
    elseif goal_travel.safe_stairs and on_travel_level then
        return { goal_travel.safe_stairs }
    elseif goal_travel.first_dir then
        return level_stairs_features(where_branch, where_depth,
            goal_travel.first_dir)
    elseif goal_travel.first_branch then
        return { branch_entrance(goal_travel.first_branch) }
    elseif on_travel_level then
        local god = goal_god(goal_status)
        if god then
            return { god_altar(god) }
        end
    end
end
