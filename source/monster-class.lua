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

--function Monster:x_pos()
--    if self.props["x_pos"] == nil then
--        self.props["x_pos"] = self.minfo:x_pos()
--    end
--
--    return self.props["x_pos"]
--end

function Monster:y_pos()
    if self.props["y_pos"] == nil then
        self.props["y_pos"] = self.minfo:y_pos()
    end

    return self.props["y_pos"]
end

function Monster:pos()
    if self.props["pos"] == nil then
        self.props["pos"] = { x = self:x_pos(), y = self:y_pos() }
    end

    return self.props["pos"]
end

function Monster:distance()
    if self.props["distance"] == nil then
        self.props["distance"] = supdist(self:pos())
    end

    return self.props["distance"]
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
    if self.props["name"] == nil then
        self.props["name"] = self.minfo:name()
    end

    return self.props["name"]
end

function Monster:desc()
    if self.props["desc"] == nil then
        self.props["desc"] = self.minfo:desc()
    end

    return self.props["desc"]
end

function Monster:speed()
    if self.props["speed"] == nil then
        self.props["speed"] = mons_speed_number(self.minfo)
    end

    return self.props["speed"]
end

function Monster:is_fast()
    if self.props["is_fast"] == nil then
        self.props["is_fast"] = self:speed() > player_speed()
    end

    return self.props["is_fast"]
end

function Monster:type()
    if self.props["type"] == nil then
        self.props["type"] = self.minfo:type()
    end

    return self.props["type"]
end

function Monster:attitude()
    if self.props["attitude"] == nil then
        self.props["attitude"] = self.minfo:attitude()
    end

    return self.props["attitude"]
end

function Monster:holiness()
    if self.props["holiness"] == nil then
        self.props["holiness"] = self.minfo:holiness()
    end

    return self.props["holiness"]
end

function Monster:res_poison()
    if self.props["res_poison"] == nil then
        self.props["res_poison"] = self.minfo:res_poison()
    end

    return self.props["res_poison"]
end

function Monster:res_draining()
    if self.props["res_draining"] == nil then
        self.props["res_draining"] = self.minfo:res_draining()
    end

    return self.props["res_draining"]
end

function Monster:is_holy_vulnerable()
    if self.props["is_holy_vulnerable"] == nil then
        local holiness = self:holiness()
        self.props["is_holy_vulnerable"] = holiness == "undead"
            or holiness == "demonic"
    end

    return self.props["is_holy_vulnerable"]
end

function Monster:is_firewood()
    if self.props["is_firewood"] == nil then
        self.props["is_firewood"] = self.minfo:is_firewood()
    end

    return self.props["is_firewood"]
end

function Monster:is_safe()
    if self.props["is_safe"] == nil then
        self.props["is_safe"] = self.minfo:is_safe()
    end

    return self.props["is_safe"]
end

function Monster:is_friendly()
    if self.props["is_friendly"] == nil then
        self.props["is_friendly"] = self:attitude() == enum_att_friendly
    end

    return self.props["is_friendly"]
end

function Monster:is_is_orc_priest_wizard()
    if self.props["is_is_orc_priest_wizard"] == nil then
        self.props["is_is_orc_priest_wizard"] = self:name() == "orc priest"
            or self:name() == "orc wizard"
    end

    return self.props["is_is_orc_priest_wizard"]
end

function Monster:ignores_player_projectiles()
    if self.props["ignores_player_projectiles"] == nil then
        self.props["ignores_player_projectiles"] = self:name() == "bush"
            or self:holiness() == "plant" and you.god() == "Fedhas"
    end

    return self.props["ignores_player_projectiles"]
end

function Monster:threat()
    if self.props["threat"] == nil then
        self.props["threat"] = self.minfo:threat()
    end

    return self.props["threat"]
end

function Monster:is_stationary()
    if self.props["is_stationary"] == nil then
        self.props["is_stationary"] = self.minfo:is_stationary()
    end

    return self.props["is_stationary"]
end

-- Adding some clua for this would be better.
function Monster:is_liquid_bound()
    if self.props["is_liquid_bound"] == nil then
        local name = self:name()
        self.props["is_liquid_bound"] = name == "electric eel"
            or name == "kraken"
            or name == "elemental wellspring"
            or name == "lava snake"
    end

    return self.props["is_liquid_bound"]
end

-- Adding some clua for this too would be better.
function Monster:can_use_stairs()
    if self.props["can_use_stairs"] == nil then
        local name = self:name()
        self.props["can_use_stairs"] =
            not (self:is_stationary()
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
    end

    return self.props["can_use_stairs"]
end

function Monster:damage_level()
    if self.props["damage_level"] == nil then
        self.props["damage_level"] = self.minfo:damage_level()
    end

    return self.props["damage_level"]
end

function Monster:is_caught()
    if self.props["is_caught"] == nil then
        self.props["is_caught"] = self.minfo:is_caught()
    end

    return self.props["is_caught"]
end

function Monster:is_summoned()
    if self.props["is_summoned"] == nil then
        self.props["is_summoned"] = self:is("summoned")
    end

    return self.props["is_summoned"]
end

function Monster:reach_range()
    if self.props["reach_range"] == nil then
        self.props["reach_range"] = self.minfo:reach_range()
    end

    return self.props["reach_range"]
end

function Monster:constricting_you()
    if self.props["constricting_you"] == nil then
        self.props["constricting_you"] = self.minfo:constricting_you()
    end

    return self.props["constricting_you"]
end

function Monster:stabbability()
    if self.props["stabbability"] == nil then
        self.props["stabbability"] = self.minfo:stabbability()
    end

    return self.props["stabbability"]
end

function Monster:is_ranged()
    if self.props["is_ranged"] == nil then
        self.props["is_ranged"] = self.minfo:has_known_ranged_attack()
            and not (self:name():find("kraken")
                or self:name() == "lost soul")
    end

    return self.props["is_ranged"]
end

-- Whether we'd ever want to attack this monster, and hence whether it's in
-- the enemy_list.
function Monster:is_enemy()
    if self.props["is_enemy"] == nil then
        self.props["is_enemy"] = not self:is_safe()
            and self:attitude() < enum_att_neutral
            and self:name() ~= "orb of destruction"
            and not (self:name():find("kraken")
                or self:name() == "lost soul")
    end

    return self.props["is_enemy"]
end

-- Whether the player can melee this monster right now.
function Monster:player_can_melee()
    if self.props["player_can_melee"] == nil then
        self.props["player_can_melee"] = player_can_melee_mons(self)
    end

    return self.props["player_can_melee"]
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
    if self.props["can_move_to_player_melee"] == nil then
        self.props["can_move_to_player_melee"] =
            mons_can_move_to_player_melee(self)
    end

    return self.props["can_move_to_player_melee"]
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

function Monster:get_player_move_towards(assume_flight)
    if not self.props.player_move then
        self.props.player_move = {}
    end

    local ind = tonumber(assume_flight)
    if self.props.player_move[ind] == nil then
        local move_func = assume_flight and flight_tabbable_square
            or tabbable_square
        self.props.player_move[ind] = get_move_towards(origin, self:pos(),
            move_func, reach_range())
    end

    return self.props.player_move[ind]
end
