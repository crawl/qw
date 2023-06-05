-----------------------------------------
-- The Monster class

util.defclass("Monster")

function Monster:new(mons)
    local monster = {}
    setmetatable(monster, self)
    monster.minfo = mons
    monster.props = {}
    return monster
end

function Monster:get_property(name, func)
    if self.props[name] == nil then
        if func then
            self.props[name] = func()
        else
            self.props[name] = self.minfo[name](self.minfo)
        end
    end

    return self.props[name]
end

function Monster:x_pos()
    return self:get_property("x_pos")
end

function Monster:y_pos()
    return self:get_property("y_pos")
end

function Monster:pos()
    return self:get_property("pos",
        function()
            return { x = self:x_pos(), y = self:y_pos() }
        end)
end

function Monster:distance()
    return self:get_property("distance",
        function()
            return supdist(self:pos())
        end)
end

function Monster:can_traverse(pos)
    if not self.props.traversal_map then
        self.props.traversal_map = {}
    end
    if not self.props.traversal_map[pos.x] then
        self.props.traversal_map[pos.x] = {}
    end
    if self.props.traversal_map[pos.x][pos.y] == nil then
        self.props.traversal_map[pos.x][pos.y] =
            self.minfo:can_traverse(pos.x, pos.y)
    end

    return self.props.traversal_map[pos.x][pos.y]
end

function Monster:name()
    return self:get_property("name")
end

function Monster:desc()
    return self:get_property("desc")
end

function Monster:speed()
    return self:get_property("speed",
        function()
            return monster_speed_number(self.minfo)
        end)
end

function Monster:is_fast()
    return self:get_property("is_fast",
        function()
            return self:speed() > player_speed()
        end)
end

function Monster:type()
    return self:get_property("type")
end

function Monster:attitude()
    return self:get_property("attitude")
end

function Monster:holiness()
    return self:get_property("holiness")
end

function Monster:res_poison()
    return self:get_property("res_poison")
end

function Monster:res_draining()
    return self:get_property("res_draining")
end

function Monster:is_holy_vulnerable()
    return self:get_property("is_holy_vulnerable",
        function()
            local holiness = self:holiness()
            return holiness == "undead" or holiness == "demonic"
        end)
end

function Monster:is_firewood()
    return self:get_property("is_firewood")
end

function Monster:is_safe()
    return self:get_property("is_safe")
end

function Monster:is_friendly()
    return self:get_property("is_friendly",
        function()
            return self:attitude() == enum_att_friendly
        end)
end

function Monster:is_orc_priest_wizard()
    return self:get_property("is_orc_priest_wizard",
        function()
            local name = self:name()
            return name == "orc priest" or name == "orc wizard"
        end)
end

function Monster:ignores_player_projectiles()
    return self:get_property("ignores_player_projectiles",
        function()
            return self:name() == "bush"
                or self:holiness() == "plant" and you.god() == "Fedhas"
        end)
end

function Monster:threat()
    return self:get_property("threat")
end

function Monster:is_stationary()
    return self:get_property("is_stationary")
end

-- Adding some clua for this would be better.
function Monster:is_liquid_bound()
    return self:get_property("is_liquid_bound",
        function()
            local name = self:name()
            return name == "electric eel"
                or name == "kraken"
                or name == "elemental wellspring"
                or name == "lava snake"
        end)
end

-- Adding some clua for this too would be better.
function Monster:can_use_stairs()
    return self:get_property("is_liquid_bound",
        function()
            local name = self:name()
            return not (self:is_stationary()
                or self:is_liquid_bound()
                or self:is_summoned()
                or name:find("zombie")
                or name:find("skeleton")
                or name:find("spectral")
                or name:find("simulacrum")
                or name:find("tentacle")
                or name:find("vortex")
                or name == "silent spectre"
                or name == "Geryon"
                or name == "Royal Jelly"
                or name == "bat"
                or name == "unseen horror"
                or name == "harpy")
        end)
end

function Monster:damage_level()
    return self:get_property("damage_level")
end

function Monster:is_caught()
    return self:get_property("is_caught")
end

function Monster:is_summoned()
    return self:get_property("is_summoned",
        function()
            return self:is("summoned")
        end)
end

function Monster:reach_range()
    return self:get_property("reach_range")
end

function Monster:is_constricted()
    return self:get_property("is_constricted")
end

function Monster:is_constricting_you()
    return self:get_property("is_constricting_you")
end

function Monster:stabbability()
    return self:get_property("stabbability")
end

function Monster:is_ranged()
    return self:get_property("is_ranged",
        function()
            return self.minfo:has_known_ranged_attack()
                and not (self:name():find("kraken")
                    or self:name() == "lost soul")
                -- We want to treat these as ranged.
                or self:name() == "obsidian statue"
        end)
end

-- Whether we'd ever want to attack this monster, and hence whether it'll be
-- put in enemy_list.
function Monster:is_enemy()
    return self:get_property("is_enemy",
        function()
            return not self:is_safe()
                and self:attitude() < enum_att_neutral
                and self:name() ~= "orb of destruction"
                and not (self:name():find("kraken")
                    or self:name() == "lost soul")
        end)
end

-- Whether the player can melee this monster right now.
function Monster:player_can_melee()
    return self:get_property("player_can_melee",
        function()
            return player_can_melee_mons(self)
        end)
end

-- Whether this monster could move close enough for the player to melee it
-- given the terrain of current LOS. This is true if the monster is already in
-- the player's melee range, or if it could traverse terrain to get close for
-- the player to melee it. By the latter we mean that the monster could get
-- within its own required melee distance to the player's current position and
-- that the player could move up to one step closer to be able to melee the
-- monster, should that be necessary. This is based on the respective melee
-- attack ranges of the monster and the player.
function Monster:can_move_to_player_melee()
    return self:get_property("can_move_to_player_melee",
        function()
            return monster_can_move_to_player_melee(self)
        end)
end

function Monster:have_line_of_fire()
    return self:get_property("player_can_ranged_attack",
        function()
            return have_line_of_fire(self:pos())
        end)
end

function Monster:adjacent_cells_known()
    return self:get_property("adjacent_cells_known",
        function()
            for pos in adjacent_iter(self:pos()) do
                if view.feature_at(pos.x, pos.y) == "unknown" then
                    return false
                end
            end
            return true
        end)
end

function Monster:is(flag)
    if not self.props.flags then
        self.props.flags = {}
    end

    if self.props.flags[flag] == nil then
        self.props.flags[flag] = self.minfo:is(flag)
    end

    return self.props.flags[flag]
end

function Monster:status(status)
    if not self.props.status then
        self.props.status = {}
    end

    if self.props.status[status] == nil then
        self.props.status[status] = self.minfo:status(status)
    end

    return self.props.status[status]
end

function Monster:player_has_path_to(assume_flight)
    if not self.props.player_has_path then
        self.props.player_has_path = {}
    end

    local ind = assume_flight and 2 or 1
    if self.props.player_has_path[ind] == nil then
        local move_func = assume_flight and flight_traversable_square
            or traversable_square
        self.props.player_has_path[ind] = get_move_towards(origin, self:pos(),
            move_func, reach_range())
    end

    return self.props.player_has_path[ind]
end

function Monster:get_player_move_towards(assume_flight)
    if not self.props.player_move then
        self.props.player_move = {}
    end

    local ind = assume_flight and 2 or 1
    if self.props.player_move[ind] == nil then
        local move_func = assume_flight and flight_tabbable_square
            or tabbable_square
        self.props.player_move[ind] = get_move_towards(origin, self:pos(),
            move_func, reach_range())
    end

    return self.props.player_move[ind]
end
