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

function Monster:property_memo(name, func)
    if self.props[name] == nil then
        local val
        if func then
            val = func()
        else
            val = self.minfo[name](self.minfo)
        end

        if val == nil then
            val = false
        end
        self.props[name] = val
    end

    return self.props[name]
end

function Monster:property_memo_args(name, func, ...)
    assert(arg.n > 0)

    local parent, key
    for j = 1, arg.n do
        if j == 1 then
            parent = self.props
            key = name
        end

        if parent[key] == nil then
            parent[key] = {}
        end

        parent = parent[key]

        key = arg[j]
        -- We turn any nil argument into false so we can pass on a valid set
        -- of args to the function. This might cause unexpected behaviour for
        -- an arbitrary function.
        if key == nil then
            key = false
            arg[j] = false
        end
    end

    if parent[key] == nil then
        local val = func()
        if val == nil then
            val = false
        end
        parent[key] = val
    end

    return parent[key]
end

function Monster:x_pos()
    return self:property_memo("x_pos")
end

function Monster:y_pos()
    return self:property_memo("y_pos")
end

function Monster:pos()
    return self:property_memo("pos",
        function()
            return { x = self:x_pos(), y = self:y_pos() }
        end)
end

function Monster:map_pos()
    return self:property_memo("map_pos",
        function()
            return position_sum(qw.map_pos, self:pos())
        end)
end

function Monster:distance()
    return self:property_memo("distance",
        function()
            return supdist(self:pos())
        end)
end

function Monster:can_use_doors()
    return self:property_memo("can_use_doors")
end

function Monster:can_traverse(pos)
    if not self.props.traversal_map then
        self.props.traversal_map = {}
    end
    if not self.props.traversal_map[pos.x] then
        self.props.traversal_map[pos.x] = {}
    end
    if self.props.traversal_map[pos.x][pos.y] == nil then
        local val = self.minfo:can_traverse(pos.x, pos.y)
        if not val and self:can_use_doors() then
            local feat = view.feature_at(pos.x, pos.y)
            val = feat == "closed_door" or feat == "closed_clear_door"
        end

        self.props.traversal_map[pos.x][pos.y] = val
    end

    return self.props.traversal_map[pos.x][pos.y]
end

function Monster:name()
    return self:property_memo("name")
end

function Monster:short_name()
    return self:property_memo("short_name",
        function()
            return monster_short_name(self)
        end)
end

function Monster:desc()
    return self:property_memo("desc")
end

function Monster:is_real_hydra()
    return self:property_memo("is_real_hydra",
        function()
            local name = self:name()
            return name:find("hydra")
                and not contains_string_in(name,
                    { "skeleton", "zombie", "simulacrum", "spectral" })
        end)
end
function Monster:move_delay()
    return self:property_memo("move_delay",
        function()
            return monster_move_delay(self)
        end)
end

function Monster:type()
    return self:property_memo("type")
end

function Monster:attitude()
    return self:property_memo("attitude")
end

function Monster:holiness()
    return self:property_memo("holiness")
end

function Monster:res_fire()
    return self:property_memo("res_fire")
end

function Monster:res_cold()
    return self:property_memo("res_cold")
end

function Monster:res_shock()
    return self:property_memo("res_shock")
end

function Monster:res_poison()
    return self:property_memo("res_poison")
end

function Monster:res_draining()
    return self:property_memo("res_draining")
end

function Monster:res_corr()
    return self:property_memo("res_corr")
end

function Monster:is_immune_vampirism()
    return self:property_memo("is_immune_vampirism",
        function()
            local holiness = self:holiness()
            return self:is_summoned()
                or self:is_harmless()
                or holiness ~= "natural" and holiness ~= "plant"
                or self:res_draining() >= 3
        end)
end

function Monster:res_holy()
    return self:property_memo("res_holy",
        function()
            local holiness = self:holiness()
            return (holiness ~= "undead" and holiness ~= "demonic") and 1 or 0
        end)
end

function Monster:is_safe()
    return self:property_memo("is_safe")
end

function Monster:is_friendly()
    return self:property_memo("is_friendly",
        function()
            return self:attitude() == const.attitude.friendly
        end)
end

function player_can_attack_monster(mons, attack_index)
    if mons:name() == "orb of destruction"
            or mons:attacking_causes_penance() then
        return false
    end

    if not attack_index then
        return true
    end

    local attack = get_attack(attack_index)
    if attack.type == const.attack.melee then
        return mons:player_can_melee()
    end

    if attack.type == const.attack.launcher then
        return not unable_to_shoot()
            and mons:player_has_line_of_fire(attack_index)
    elseif attack.type == const.attack.throw then
        return not unable_to_throw()
            and mons:player_has_line_of_fire(attack_index)
    elseif attack.type == const.attack.evoke then
        return can_evoke() and mons:player_has_line_of_fire(attack_index)
    end
end

function Monster:player_can_attack(attack_index)
    return self:property_memo_args("player_can_attack",
        function()
            return player_can_attack_monster(self, attack_index)
        end, attack_index)
end

function Monster:attacking_causes_penance()
    return self:property_memo("attacking_causes_penance",
        function()
            return self:attitude() > const.attitude.hostile and is_good_god()
                or self:attitude() == const.attitude.strict_neutral
                    and you.god() == "Jiyva"
                or self:is_friendly()
                    and you.god() == "Beogh"
                    -- XXX: For simplicity, just assume any non-summoned
                    -- friendly is a follower orc.
                    and not self:is_summoned()
        end)
end

function Monster:is_orc_priest_wizard()
    return self:property_memo("is_orc_priest_wizard",
        function()
            local name = self:name()
            return name == "orc priest" or name == "orc wizard"
        end)
end

-- Monsters here will be target with ranged attacks even if they're not the
-- closest monster.
function Monster:los_danger()
    return self:property_memo("los_danger",
        function()
            local name = self:name()
            return name == "doom hound" and self:is("ready_to_howl")
                or name == "draconian shifter"
                or name == "dream sheep"
                or name == "entropy weaver"
                or name == "glass eye"
                or name == "guardian serpent"
                or name == "hellion"
                or name == "moth of wrath"
                or name == "torpor snail"
        end)
end

function Monster:ignores_player_projectiles()
    return self:property_memo("ignores_player_projectiles",
        function()
            return self:name() == "bush"
                or self:name() == "orb of destruction"
                or self:holiness() == "plant" and you.god() == "Fedhas"
                or self:name():find("^elliptic") and you.god() == "Hepliaklqana"
        end)
end

function Monster:threat(duration_level)
    return self:property_memo_args("threat",
        function()
            return monster_threat(self, duration_level)
        end, duration_level)
end

function Monster:hp()
    return self:property_memo("hp",
        function()
            local hp = self.minfo:max_hp():gsub(".-(%d+).*", "%1")
            return tonumber(hp)
                -- The scaling factor takes the midpoint hitpoint value for the
                -- damage level.
                * min(1, max(0, (10 - 2 * self.minfo:damage_level() + 1) / 10))
        end)
end

function Monster:player_attack_damage(index, duration)
    return self:property_memo_args("player_attack_damage",
        function()
            return player_attack_damage(self, index, duration)
        end, index, duration)
end

function Monster:best_player_attack()
    return self:property_memo("best_player_attack",
        function() return monster_best_player_attack(self) end)
end

function Monster:is_stationary()
    return self:property_memo("is_stationary")
end

-- Adding some clua for this would be better.
function Monster:is_liquid_bound()
    return self:property_memo("is_liquid_bound",
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
    return self:property_memo("can_use_upstairs",
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
    return self:property_memo("damage_level")
end

function Monster:is_caught()
    return self:property_memo("is_caught")
end

function Monster:is_summoned()
    return self:property_memo("is_summoned",
        function()
            return self:is("summoned")
        end)
end

function Monster:reach_range()
    return self:property_memo("reach_range")
end

function Monster:is_constricted()
    return self:property_memo("is_constricted")
end

function Monster:is_constricting_you()
    return self:property_memo("is_constricting_you")
end

function Monster:stabbability()
    return self:property_memo("stabbability")
end

function Monster:is_ranged(ignore_reach)
    return self:property_memo_args("is_ranged",
        function()
            return self.minfo:has_known_ranged_attack()
                    and not (ignore_reach and self:reach_range() > 1
                        or self:name():find("kraken")
                        or self:name() == "lost soul")
                -- We want to treat these as ranged.
                or self:name() == "obsidian statue"
        end, ignore_reach)
end

function Monster:is_harmless()
    return self:property_memo("is_harmless",
        function()
            return self.minfo:is_firewood() or self:name() == "butterfly"
        end)
end

-- Whether we'd ever want to attack this monster, and hence whether it'll be
-- put in the enemy list.
function Monster:is_enemy()
    return self:property_memo("is_enemy",
        function()
            if self:is_harmless() then
                return false
            end

            if self:name() == "orb of destruction" then
                return false
            end

            local attitude = self:attitude()
            return attitude < const.attitude.neutral
                or attitude == const.attitude.neutral and self:is("frenzied")
        end)
end

-- Whether the player can melee this monster right now.
function Monster:player_can_melee()
    return self:property_memo("player_can_melee",
        function()
            return player_can_melee_mons(self)
        end)
end

function Monster:is_unalert()
    return self:property_memo("is_unalert",
        function()
            return self:is("sleeping")
                or self:is("dormant")
                or self:is("wandering")
        end)
end

function Monster:can_seek(ignore_temporary)
    return self:property_memo_args("can_seek",
        function()
            if self:is_stationary()
                    or self:is_unalert()
                    or self:name() == "wandering mushroom"
                    or self:name():find("vortex") then
                return false
            end

            if ignore_temporary then
                return true
            end

            return not (self:is_caught()
                or self:is_constricted()
                or self:is("fleeing")
                or self:status("paralysed")
                or self:status("confused")
                or self:status("petrified")
                or self:status("constricted by roots"))
        end, ignore_temporary)
end

function Monster:can_melee_at(pos)
    if not self.props.can_melee_at then
        self.props.can_melee_at = {}
    end
    if not self.props.can_melee_at[pos.x] then
        self.props.can_melee_at[pos.x] = {}
    end

    if self.props.can_melee_at[pos.x][pos.y] ~= nil then
        return self.props.can_melee_at[pos.x][pos.y]
    end

    local can_melee = positions_can_melee(self:pos(), pos, self:reach_range())
    self.props.can_melee_at[pos.x][pos.y] = can_melee
    return can_melee
end

function Monster:can_melee_player()
    return self:can_melee_at(const.origin)
end

function Monster:melee_move_search(pos)
    if not self.props.melee_move_search then
        self.props.melee_move_search = {}
    end
    if not self.props.melee_move_search[pos.x] then
        self.props.melee_move_search[pos.x] = {}
    end

    if self.props.melee_move_search[pos.x][pos.y] ~= nil then
        return self.props.melee_move_search[pos.x][pos.y]
    end

    if not self:can_seek(true) then
        self.props.melee_move_search[pos.x][pos.y] = false
        return false
    end

    local square_func = function(pos)
        return self:can_traverse(pos)
    end
    local result = move_search(self:pos(), pos, square_func,
        self:reach_range())
    self.props.melee_move_search[pos.x][pos.y] = result
    return result
end

function Monster:melee_move_distance(pos)
    if position_distance(self:pos(), pos) <= self:reach_range() then
        return 0
    end

    local result = self:melee_move_search(pos)
    if result then
        return result.dist
    else
        return const.inf_dist
    end
end

--[[
Whether this monster has a path it can take to melee the player. This includes
the case where the monster is already in range to melee.

@treturn boolean True if the monster has such a path, false otherwise.
]]--
function Monster:has_path_to_melee_player()
    return self:property_memo("has_path_to_melee_player",
        function()
            if self:can_melee_player() then
                return true
            end

            return self:melee_move_search(const.origin)
        end)
end

--[[
Whether this monster has a path it can take to get adjacent to the player.
This includes the case where the monster is already adjacent.

@treturn boolean True if the monster has such a path, false otherwise.
]]--
function Monster:has_path_to_player()
    return self:property_memo("has_path_to_player",
        function()
            if not self:can_seek() then
                return false
            end

            if position_distance(self:pos(), const.origin) == 1 then
                return true
            end

            local square_func = function(pos)
                return self:can_traverse(pos)
            end
            return move_search(self:pos(), const.origin, square_func, 1)
        end)
end

function Monster:player_can_wait_for_melee()
    return self:property_memo("player_can_wait_for_melee",
        function()
            return not self:player_can_melee()
                and self:has_path_to_melee_player()
                and (self:reach_range() <= player_reach_range()
                        or get_move_closer(self:pos()))
                and self:distance() > self:reach_range()
        end)
end

function Monster:player_has_line_of_fire(attack_id)
    return self:property_memo_args("player_has_line_of_fire",
        function()
            return player_has_line_of_fire(self:pos(), attack_id)
        end, attack_id)
end

function Monster:adjacent_cells_known()
    return self:property_memo("adjacent_cells_known",
        function()
            for pos in adjacent_iter(self:pos()) do
                if view.feature_at(pos.x, pos.y) == "unseen" then
                    return false
                end
            end
            return true
        end)
end

function Monster:should_dig_unreachable()
    return self:property_memo("should_dig_unreachable",
        function()
            return should_dig_unreachable_monster(self)
        end)
end

function Monster:is(flag)
    return self:property_memo_args("is",
        function()
            return self.minfo:is(flag)
        end, flag)
end

function Monster:status(status)
    return self:property_memo_args("status",
        function()
            return self.minfo:status(status)
        end, status)
end

function Monster:player_has_path_to_melee()
    return self:property_memo("player_has_path_to_melee",
        function()
            if self:player_can_melee() then
                return true
            end

            return move_search(const.origin, self:pos(),
                traversal_function(), player_reach_range())
        end)
end

function Monster:get_player_move_towards(assume_flight)
    return self:property_memo_args("get_player_move_towards",
        function()
            local result = move_search(const.origin, self:pos(),
                tab_function(assume_flight), player_reach_range())
            return result and result.move or false
        end, assume_flight)
end

function Monster:weapon_accuracy(item)
    return self:property_memo_args("weapon_accuracy",
        function()
            local str = self.minfo:target_weapon(item)
            str = str:gsub(".-(%d+)%% to hit.*", "%1")
            return tonumber(str) / 100
        end, item)
end

function Monster:throw_accuracy(item)
    return self:property_memo_args("throw_accuracy",
        function()
            local str = self.minfo:target_throw(item)
            str = str:gsub(".-(%d+)%% to hit.*", "%1")
            return tonumber(str) / 100
        end, item)
end

function Monster:evoke_accuracy(item)
    return self:property_memo_args("evoke_accuracy",
        function()
            local str = self.minfo:target_evoke(item)
            if empty_string(str) then
                return 1
            end

            -- Comes in two forms: "XX% to hit" and "chance to affect: XX%".
            str = str:gsub(".-(%d+)%%.*", "%1")
            local perc = tonumber(str)
            if not perc then
                return 0
            end

            return perc / 100
        end, item)
end
