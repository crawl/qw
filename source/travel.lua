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

function travel_branch_levels(branch, start_depth, dest_depth)
    local dir = sign(dest_depth - start_depth)
    local depth = start_depth
    while depth ~= dest_depth do
        if count_stairs(branch, depth, dir, FEAT_LOS.SEEN) == 0 then
            return depth
        end

        depth = depth + dir
    end

    return depth
end

function travel_up_branches(start_branch, start_depth, parents, entries,
        dest_branch)
    local branch = start_branch
    local depth = start_depth
    local i = 1
    for i = 1, #parents do
        if branch == dest_branch then
            break
        end

        if is_hell_branch(branch) then
            if not branch_found(branch)
                    or parents[i] ~= parent_branch(branch) then
                break
            end
        else
            depth = travel_branch_levels(branch, depth, 1)
            if depth ~= 1 then
                break
            end
        end

        branch = parents[i]
        depth = entries[branch]
    end

    return branch, depth
end

function travel_down_branches(dest_branch, dest_depth, parents, entries)
    local i = #parents
    local branch, depth, stop_branch
    for i = #parents, 1, -1 do
        branch = parents[i]
        depth = entries[branch]

        -- Try to travel into our next branch.
        local next_depth
        if i > 1 then
            local next_parent = parents[i - 1]
            if not branch_found(next_parent)
                    -- A branch we can't actually enter with travel.
                    or not branch_travel(next_parent) then
                stop_branch = next_parent
                break
            end
            branch = next_parent
            next_depth = entries[branch]
        else
            if not branch_found(dest_branch)
                    or not branch_travel(dest_branch) then
                stop_branch = dest_branch
                break
            end
            branch = dest_branch
            next_depth = dest_depth
        end
        depth = 1

        depth = travel_branch_levels(branch, depth, next_depth)
        if depth ~= next_depth then
            break
        end

        i = i - 1
    end

    return branch, depth, stop_branch
end

-- Search branch and stair data from a starting level to a destination level,
-- returning the furthest point to which we know we can travel.
-- @string  start_branch The starting branch.
-- @int     start_depth  The starting depth.
-- @string  dest_branch  The destination branch.
-- @int     dest_depth   The destination depth.
-- @treturn string       The furthest branch traveled.
-- @treturn int          The furthest depth traveled in the furthest branch.
-- @treturn string       Any branch whose entry we were not able to travel into
--                       at the furthest location travel.
function travel_destination_search(dest_branch, dest_depth, start_branch,
        start_depth)
    if not start_branch then
        start_branch = where_branch
    end
    if not start_depth then
        start_depth = where_depth
    end

    -- We're already there.
    if start_branch == dest_branch and start_depth == dest_depth then
        return dest_branch, dest_depth
    end

    local common_parent, start_parents, start_entries, dest_parents,
        dest_entries
    if start_branch == dest_branch
            and (not is_hell_branch(start_branch)
                or start_depth <= dest_depth) then
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

    local cur_branch = start_branch
    local cur_depth = start_depth
    -- Travel up and out of the starting branch until we reach the common
    -- parent branch. Don't bother traveling up if the destination branch is a
    -- sub-branch of the starting branch.
    if start_branch ~= common_parent then
        cur_branch, cur_depth = travel_up_branches(cur_branch, cur_depth,
            start_parents, start_entries, common_parent)

        -- We weren't able to travel all the way up to the common parent.
        if cur_depth ~= start_entries[common_parent] then
            return cur_branch, cur_depth
        end
    end

    -- We've already arrived at our ultimate destination.
    if cur_branch == dest_branch and cur_depth == dest_depth then
        return cur_branch, cur_depth
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
    cur_depth = travel_branch_levels(common_parent, cur_depth, next_depth)

    -- We couldn't make it to the branch entry we need.
    if cur_depth ~= next_depth then
        return cur_branch, cur_depth
    -- We already arrived at our ultimate destination.
    elseif cur_branch == dest_branch and cur_depth == dest_depth then
        return cur_branch, cur_depth
    end

    -- Travel into and down branches to reach our ultimate destination. We're
    -- always starting at the first branch entry we'll need to take.
    cur_branch, cur_depth, stop_branch = travel_down_branches(dest_branch,
        dest_depth, dest_parents, dest_entries)
    return cur_branch, cur_depth, stop_branch
end

function check_depth_dir(branch, depth, dir)
    local dir_depth = depth + dir
    -- We can already reach all required stairs in this direction on our level.
    if count_stairs(branch, depth, dir, FEAT_LOS.REACHABLE)
            == num_required_stairs(branch, depth, dir) then
        return
    end

    local dir_depth_stairs =
        count_stairs(branch, dir_depth, -dir, FEAT_LOS.EXPLORED)
            < count_stairs(branch, dir_depth, -dir, FEAT_LOS.REACHABLE)
    -- The adjacent level in this direction from our level is autoexplored and
    -- we have no unexplored reachable stairs remaining on that level in the
    -- opposite direction.
    if autoexplored_level(branch, dir_depth) and not dir_depth_stairs then
        -- The reachable stairs in this direction on our level are also all
        -- explored, hence we've done as much as we can with this direction
        -- relative to our level.
        if count_stairs(branch, depth, dir, FEAT_LOS.REACHABLE)
                == count_stairs(branch, depth, dir, FEAT_LOS.EXPLORED) then
            return
        end

        return depth, dir
    end

    -- Only try a stair search on the adjacent level if we know there are
    -- unexplored stairs we could take. Otherwise explore the adjacent level,
    -- looking for relevant stairs.
    if dir_depth_stairs then
        return dir_depth, -dir
    else
        return dir_depth
    end
end

function finalize_travel_depth(branch, depth)
    if not autoexplored_level(branch, depth) then
        return depth
    end

    local up_reachable = depth > 1
        and count_stairs(branch, depth, DIR.UP, FEAT_LOS.REACHABLE) > 0
    local final_depth, final_dir
    if up_reachable then
        final_depth, final_dir = check_depth_dir(branch, depth, DIR.UP)
    end

    local down_reachable = depth < branch_depth(branch)
        and count_stairs(branch, depth, DIR.DOWN, FEAT_LOS.REACHABLE) > 0
    if not final_depth and down_reachable then
        final_depth, final_dir = check_depth_dir(branch, depth, DIR.DOWN)
    end

    if not final_depth then
        if up_reachable
                -- Don't reset up stairs if we still need the branch rune,
                -- since we have specific plans for branch ends we may need to
                -- follow.
                and (have_branch_runes(branch)
                    or depth < branch_rune_depth(branch)) then
            level_stair_reset(branch, depth, DIR.UP)
            level_stair_reset(branch, depth - 1, DIR.DOWN)
            final_depth = depth - 1
            final_dir = DIR.DOWN
        end

        if down_reachable then
            level_stair_reset(branch, depth, DIR.DOWN)
            level_stair_reset(branch, depth + 1, DIR.UP)
            if not final_depth then
                final_depth = depth + 1
                final_dir = DIR.UP
            end
        end
    end

    if not final_depth then
        final_depth = depth
    end

    return final_depth, final_dir
end

function travel_destination(dest_branch, dest_depth, stash_travel)
    if not dest_branch or in_portal() then
        return
    end

    local dir
    local branch, depth, stop_branch = travel_destination_search(dest_branch,
        dest_depth)

    -- We were unable enter the branch in stop_branch, so figure out the next
    -- best location to travel to in its parent branch.
    if stop_branch and not branch_found(stop_branch) then
        local parent, min_depth, max_depth = parent_branch(stop_branch)
        depth = next_exploration_depth(parent, min_depth, max_depth)
        depth, dir = finalize_travel_depth(branch, depth)
    -- Get the final depth we should travel to given the state of stair
    -- exploration at our travel destination. For stash search travel, we don't
    -- do this, since we know what we want is on the destination level.
    elseif not stash_travel then
        depth, dir = finalize_travel_depth(branch, depth)
    end

    return branch, depth, dir
end

function update_gameplan_travel()
    -- We use a stash search to reach our destination, but will still do a
    -- travel search for any given gameplan branch/depth, so we can use a go
    -- command as a backup.
    local stash_travel = gameplan_status == "Orb" and c_persist.found_orb
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

    travel_branch, travel_depth, stairs_search_dir
        = travel_destination(gameplan_branch, gameplan_depth, stash_travel)
    want_go_travel = (travel_branch
            and (where_branch ~= travel_branch or where_depth ~= travel_depth))

    -- Don't autoexplore if we want to travel in some way. This is so we can
    -- leave our current level before it's completely explored.
    disable_autoexplore = (stairs_search_dir or want_go_travel or stash_travel)
            -- We do allow autoexplore even when we want to travel if the
            -- current is fully explored, since then it's safe to pick up any
            -- surrounding items like thrown projectiles or loot from e.g.
            -- stairdancing. However we don't allow autoexplore in this case if
            -- our current level is our travel destination. This exception is
            -- to allow within-level plans like taking unexplored stairs and
            -- stash searches to on-level destinations to not be interrupted if
            -- autoexplore would move us next to a runed door.
            and (not explored_level(where_branch, where_depth)
                or (travel_branch and not want_go_travel))

    if DEBUG_MODE then
        dsay("Stash travel: " .. bool_string(stash_travel), "explore")
        dsay("Travel branch: " .. tostring(travel_branch) .. ", depth: "
            .. tostring(travel_depth) .. ", stairs search dir: "
            .. tostring(stairs_search_dir), "explore")
        dsay("Want go travel: " .. bool_string(want_go_travel), "explore")
        dsay("Disable autoexplore: " .. bool_string(disable_autoexplore),
            "explore")
    end
end
