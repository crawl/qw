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
        -- branch, this will be handled later in update_gameplan_travel().
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
        if count_stairs(result.branch, result.depth, dir, FEAT_LOS.SEEN)
                == 0 then
            return
        end

        result.depth = result.depth + dir
    end
end

function travel_up_branches(result, parents, entries, dest_branch)
    if not result.first_dir and not result.first_branch then
        result.first_dir = DIR.UP
    end

    local i = 1
    for i = 1, #parents do
        if result.branch == dest_branch then
            return
        end

        if is_hell_branch(result.branch) then
            if not branch_found(result.branch)
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
            next_depth = entries[result.branch]
        else
            next_branch = dest_branch
            next_depth = dest_depth
        end

        -- We stop if we haven't found the next branch or if we can't actually
        -- enter it with travel.
        if not branch_found(next_branch)
                or not branch_travel(next_branch) then
            result.stop_branch = next_branch
            break
        end

        result.branch = next_branch
        result.depth = 1
        if not result.first_dir and not result.first_branch then
            result.first_branch = result.branch
        end

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

function finalize_depth_dir(result, dir)
    assert(type(dir) == "number" and abs(dir) == 1,
        "Invalid stair direction: " .. tostring(dir))

    local dir_depth = result.depth + dir
    -- We can already reach all required stairs in this direction on our level.
    if count_stairs(result.branch, result.depth, dir, FEAT_LOS.REACHABLE)
            == num_required_stairs(result.branch, depth, dir) then
        return false
    end

    local dir_depth_stairs =
        count_stairs(result.branch, dir_depth, -dir, FEAT_LOS.EXPLORED)
            < count_stairs(result.branch, dir_depth, -dir, FEAT_LOS.REACHABLE)
    -- The adjacent level in this direction from our level is autoexplored and
    -- we have no unexplored reachable stairs remaining on that level in the
    -- opposite direction.
    if autoexplored_level(result.branch, dir_depth)
            and not dir_depth_stairs then
        -- The reachable stairs in this direction on our level are also all
        -- explored, hence we've done as much as we can with this direction
        -- relative to our level.
        if count_stairs(result.branch, result.depth, dir, FEAT_LOS.REACHABLE)
                == count_stairs(result.branch, result.depth, dir,
                    FEAT_LOS.EXPLORED) then
            return false
        end

        result.stairs_dir = dir
        if not result.first_dir and not result.first_branch then
            result.first_dir = dir
        end
        return true
    end

    if not result.first_dir and not result.first_branch then
        result.first_dir = dir
    end
    result.depth = dir_depth

    -- Only try a stair search on the adjacent level if we know there are
    -- unexplored stairs we could take. Otherwise explore the adjacent level,
    -- looking for relevant stairs.
    if dir_depth_stairs then
        result.stairs_dir = -dir
    end

    return true
end

function finalize_travel_depth(result)
    if not autoexplored_level(result.branch, result.depth) then
        return
    end

    local up_reachable = result.depth > 1
        and count_stairs(result.branch, result.depth, DIR.UP,
            FEAT_LOS.REACHABLE) > 0
    local finished
    if up_reachable then
        finished = finalize_depth_dir(result, DIR.UP)
    end

    local down_reachable = result.depth < branch_depth(result.branch)
        and count_stairs(result.branch, result.depth, DIR.DOWN,
            FEAT_LOS.REACHABLE) > 0
    if not finished and down_reachable then
        finished = finalize_depth_dir(result, DIR.DOWN)
    end

    if not finished then
        if up_reachable
                -- Don't reset up stairs if we still need the branch rune,
                -- since we have specific plans for branch ends we may need to
                -- follow.
                and (have_branch_runes(result.branch)
                    or result.depth < branch_rune_depth(result.branch)) then
            stairs_reset(result.branch, result.depth, DIR.UP)
            stairs_reset(result.branch, result.depth - 1, DIR.DOWN)
            if not result.first_dir and not result.first_branch then
                result.first_dir = DIR.UP
            end
            result.depth = result.depth - 1
            result.stairs_dir = DIR.UP
            finished = true
        end

        if down_reachable then
            stairs_reset(result.branch, result.depth, DIR.DOWN)
            stairs_reset(result.branch, result.depth + 1, DIR.UP)
            -- If we've just reset up stairs, that direction gets priority as
            -- the first search destination.
            if not finished then
                result.depth = result.depth + 1
                if not result.first_dir and not result.first_branch then
                    result.first_dir = DIR.DOWN
                end
                result.stairs_dir = DIR.UP
            end
        end
    end
end

function travel_destination(dest_branch, dest_depth, stash_travel)
    if not dest_branch or in_portal() then
        return {}
    end

    local result = travel_destination_search(dest_branch, dest_depth)
    -- We were unable enter the branch in result.stop_branch, so figure out the
    -- next best travel location in the branch's parent.
    if result.stop_branch and not branch_found(result.stop_branch) then
        local parent, min_depth, max_depth = parent_branch(result.stop_branch)
        result.branch = parent
        result.depth = next_exploration_depth(parent, min_depth, max_depth)
        finalize_travel_depth(result)
    -- Get the final depth we should travel to given the state of stair
    -- exploration at our travel destination. For stash search travel, we don't
    -- do this, since we know what we want is on the destination level.
    elseif not stash_travel then
        finalize_travel_depth(result)
    end

    return result
end

function update_gameplan_travel()
    -- We use a stash search to reach our destination, but will still do a
    -- travel search for any given gameplan branch/depth, so we can use a go
    -- command as a backup.
    local want_stash = gameplan_status == "Orb" and c_persist.found_orb
        or not gameplan_branch
        or gameplan_status:find("^God") and gameplan_branch ~= "Temple"
        or is_portal_branch(gameplan_branch)
            and not in_portal()
            and branch_found(gameplan_branch)
        or gameplan_branch == "Abyss"
            and where_branch ~= "Abyss"
            and branch_found("Abyss")
        or gameplan_branch == "Pan"
            and where_branch ~= "Pan"
            and branch_found("Pan")

    gameplan_travel = travel_destination(gameplan_branch, gameplan_depth,
        want_stash)
    gameplan_travel.want_stash = want_stash
    gameplan_travel.want_go = gameplan_travel.branch
        and (where_branch ~= gameplan_travel.branch
            or where_depth ~= gameplan_travel.depth)

    -- Don't autoexplore if we want to travel in some way. This allows us to
    -- leave the level before it's completely explored.
    disable_autoexplore = (gameplan_travel.stairs_dir
            or gameplan_travel.want_go
            or gameplan_travel.want_stash)
        -- We do allow autoexplore even when we want to travel if the current
        -- is fully explored, since then it's safe to pick up any surrounding
        -- items like thrown projectiles or loot from e.g. stairdancing.
        and (not explored_level(where_branch, where_depth)
        -- However we don't allow autoexplore in this case if our current level
        -- is our travel destination. This exception is to allow within-level
        -- plans like taking unexplored stairs and stash searches to on-level
        -- destinations like altars to not be interrupted when runed doors
        -- exist. In that case autoexplore would move us next to a runed door
        -- and off of our intermediate stair/altar/etc. where we need to be.
            or (gameplan_travel.branch and not gameplan_travel.want_go))

    if debug_channel("explore") then
        dsay("Travel branch: " .. tostring(gameplan_travel.branch)
            ..  ", depth: " .. tostring(gameplan_travel.depth))
        if gameplan_travel.stairs_dir then
            dsay("Stairs search dir: " .. tostring(gameplan_travel.stairs_dir))
        end
        if gameplan_travel.first_dir then
            dsay("First dir: " .. tostring(gameplan_travel.first_dir))
        end
        if gameplan_travel.first_branch then
            dsay("First branch: " .. tostring(gameplan_travel.first_branch))
        end
        dsay("Want stash travel: " .. bool_string(want_stash))
        dsay("Want go travel: " .. bool_string(gameplan_travel.want_go))
        dsay("Disable autoexplore: " .. bool_string(disable_autoexplore))
    end
end
