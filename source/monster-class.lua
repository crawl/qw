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

-- Memoize a property read from a CLua api monster info function.
function Monster:property_memo(name)
    local val = self.props[name]
    if val == nil then
        val = self.minfo[name](self.minfo)
        if val == nil then
            val = false
        end
        self.props[name] = val
    end

    return val
end

-- Memoize a function that takes no arguments. This memo function is a bit
-- faster than Monster:function_memo_args.
function Monster:function_memo(func)
    local val = self.props[func]
    if val == nil then
        val = func(self)
        if val == nil then
            val = false
        end
        self.props[func] = val
    end

    return val
end

-- Memoize a function that takes a fixed number of arguments. The number of
-- arguments passed to func shouldn't vary, which will be the case so long as
-- the caller of Monster:function_memo_args() declares its arguments and
-- doesn't use variable arguments.
function Monster:function_memo_args(func, ...)
    local args = table.pack(...)
    assert(args.n > 0)

    local parent, key
    for j = 1, args.n do
        if j == 1 then
            parent = self.props
            key = func
        end

        local child = parent[key]
        if child == nil then
            child = {}
            parent[key] = child
        end
        parent = child

        key = args[j]
        if key == nil then
            key = false
        -- A position table. The position hash is the key.
        elseif type(key) == "table" then
            key = key.hash
            assert(key)
        end
    end

    -- Obtain the actual value for this combination of arguments.
    local val = parent[key]
    if val == nil then
        val = func(self, ...)
        if val == nil then
            val = false
        end
        parent[key] = val
    end

    return val
end

function Monster:x_pos()
    return self:property_memo("x_pos")
end

function Monster:y_pos()
    return self:property_memo("y_pos")
end

function Monster:can_use_doors()
    return self:property_memo("can_use_doors")
end

function Monster:name()
    return self:property_memo("name")
end

function Monster:desc()
    return self:property_memo("desc")
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

function Monster:is_safe()
    return self:property_memo("is_safe")
end

function Monster:is_stationary()
    return self:property_memo("is_stationary")
end

function Monster:damage_level()
    return self:property_memo("damage_level")
end

function Monster:is_caught()
    return self:property_memo("is_caught")
end

function Monster:range()
    return self:property_memo("range")
end

function Monster:melee_range()
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

function Monster:intelligence()
    return self:property_memo("intelligence")
end

function Monster:is_firewood()
    return self:property_memo("is_firewood")
end

function Monster:_pos()
    return new_position(self:x_pos(), self:y_pos())
end

function Monster:pos()
    return self:function_memo(self._pos)
end

function Monster:_map_pos()
    return map_position(self:pos())
end

function Monster:map_pos()
    return self:function_memo(self._map_pos)
end

function Monster:_distance()
    return supdist(self:pos())
end

function Monster:distance()
    return self:function_memo(self._distance)
end

function Monster:_can_traverse(pos)
    local can_traverse = self.minfo:can_traverse(pos.x, pos.y)
    if can_traverse then
        return true
    -- If we can't traverse this feature because it's a closed door we could
    -- open, we can traverse this position.
    elseif self:can_use_doors() then
        local feat = feature_at(pos)
        return feat == "closed_door" or feat == "closed_clear_door"
    else
        return false
    end
end

function Monster:can_traverse(pos)
    return self:function_memo_args(self._can_traverse, pos)
end

function Monster:_short_name()
    return monster_short_name(self)
end

function Monster:short_name()
    return self:function_memo(self._short_name)
end

function Monster:_summoner()
    local x, y = self.minfo:summoner_pos()
    if not x then
        return
    end

    return get_monster_at(new_position(x, y))
end

function Monster:summoner()
    return self:function_memo(self._summoner)
end

function Monster:_regrows_heads()
    local name = self:name()
    return (name:find("hydra") or name:find("slymdra"))
        and not contains_string_in(name,
            { "skeleton", "zombie", "simulacrum", "spectral" })
end

function Monster:regrows_heads()
    return self:function_memo(self._regrows_heads)
end

function Monster:move_delay()
    return self:function_memo(monster_move_delay)
end

function Monster:_is_immune_vampirism()
    local holiness = self:holiness()
    return self:is_summoned()
        or self:is_harmless()
        or holiness ~= "natural" and holiness ~= "plant"
        or self:res_draining() >= 3
end

function Monster:is_immune_vampirism()
    return self:function_memo(self._is_immune_vampirism)
end

function Monster:_res_holy()
    local holiness = self:holiness()
    return (holiness ~= "undead" and holiness ~= "demonic") and 1 or 0
end

function Monster:res_holy()
    return self:function_memo(self._res_holy)
end

function Monster:_is_friendly()
    return self:attitude() == const.attitude.friendly
end

function Monster:is_friendly()
    return self:function_memo(self._is_friendly)
end

function Monster:_player_can_attack()
    return self:name() ~= "orb of destruction"
        and not self:attacking_causes_penance()
end

function Monster:player_can_attack()
    return self:function_memo(self._player_can_attack)
end

function Monster:player_attack_can_hit(attack_index)
    return self:function_memo_args(mons_player_attack_can_hit, attack_index)
end

function Monster:_attacking_causes_penance()
    return self:attitude() > const.attitude.hostile and is_good_god()
        or self:attitude() == const.attitude.strict_neutral
            and you.god() == "Jiyva"
        or self:is_friendly()
            and you.god() == "Beogh"
            -- XXX: For simplicity, just assume any non-summoned
            -- friendly is a follower orc.
            and not self:is_summoned()
end

function Monster:attacking_causes_penance()
    return self:function_memo(self._attacking_causes_penance)
end

-- We cache all of a monster's spells the first time a spell is queried.
function Monster:_has_spell(spell)
    if self.props.spells then
        return self.props.spells[spell]
    end

    local spells = {}
    for _, sp in ipairs(self.minfo:spells()) do
        spells[sp] = true
    end

    self.props.spells = spells
    return spells[spell]
end

function Monster:has_spell(spell)
    return self:function_memo_args(self._has_spell, spell)
end

function Monster:_is_summoner()
    return self:has_spell("Abjuration")
end

function Monster:is_summoner()
    return self:function_memo(self._is_summoner)
end

-- Monsters with these spells will be target with ranged attacks even if
-- they're not the closest monster.
local los_danger_spells = {
    "Berserk Other", "Confusion Gaze", "Doom Howl", "Dream Dust",
    "Entropic Weave", "Vitrifying Gaze", "Weakening Gaze", "Word of Recall"
}
function Monster:_los_danger()
    -- Slowness aura
    if self:name() == "torpor snail" then
        return true
    end

    for _, spell in ipairs(los_danger_spells) do
        if self:has_spell(spell)
                and not (spell == "Weakening Gaze"
                    and using_ranged_weapon())
                and not (spell == "Doom Howl"
                    and not self:is("ready_to_howl")) then
            return true
        end
    end

    return false
end

function Monster:los_danger()
    return self:function_memo(self._los_danger)
end

-- Monsters with a gaze or smite-targeted attack.
local los_spells = {
    "Airstrike", "Blink Allies Encircling", "Call Down Damnation",
    "Call Down Lightning", "Drain Life", "Eruption", "Fire Storm", "Glaciate",
    "Grasping Roots", "Lee's Rapid Deconstruction", "Ozocubu's Refrigeration",
    "Polar Vortex", "Portal Projectile", "Pyroclastic Surge", "Smiting",
    "Symbol of Torment", "Upheaval"
}
function Monster:_can_attack_los()
    if self:los_danger() then
        return true
    end

    for _, spell in ipairs(los_spells) do
        if self:has_spell(spell)
                and (spell ~= "Lee's Rapid Deconstruction"
                    or you.race() == "Gargoyle")
                and (spell ~= "Drain Life"
                    or you.res_draining() < 3) then
            return true
        end
    end

    return false
end

function Monster:can_attack_los()
    return self:function_memo(self._can_attack_los)
end

function Monster:_ignores_player_projectiles()
    return self:name() == "bush"
        or self:name() == "orb of destruction"
        or self:holiness() == "plant" and you.god() == "Fedhas"
        or self:name():find("^elliptic")
            and you.god() == "Hepliaklqana"
end

function Monster:ignores_player_projectiles()
    return self:function_memo(self._ignores_player_projectiles)
end

function Monster:threat(duration_level, consider_hp)
    return self:function_memo_args(monster_threat, duration_level, consider_hp)
end

function Monster:_hp_fraction()
    -- The scaling factor takes the midpoint hitpoint value for the damage
    -- level.
    return min(1,
        max(0, (10 - 2 * self.minfo:damage_level() + 1) / 10))
end

function Monster:hp_fraction()
    return self:function_memo(self._hp_fraction)
end

function Monster:_hp()
    local hp = tonumber((self.minfo:max_hp():gsub(".-(%d+).*", "%1")))
    return hp * self:hp_fraction()
end

function Monster:hp()
    return self:function_memo(self._hp)
end

function Monster:player_attack_damage(index, duration)
    return self:function_memo_args(player_attack_damage, index, duration)
end

function Monster:best_player_attack()
    return self:function_memo(mons_best_player_attack)
end

-- Adding some clua for this would be better.
function Monster:_is_liquid_bound()
    local name = self:name()
    return name == "electric eel"
        or name == "kraken"
        or name == "elemental wellspring"
        or name == "lava snake"
end

function Monster:is_liquid_bound()
    return self:function_memo(self._is_liquid_bound)
end

-- Adding some clua for this too would be better.
function Monster:_can_use_stairs()
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
end

function Monster:can_use_stairs()
    return self:function_memo(self._can_use_stairs)
end

function Monster:_is_summoned()
    return self:is("summoned")
end

function Monster:is_summoned()
    return self:function_memo(self._is_summoned)
end

function Monster:_is_ranged()
    if self:los_danger() or self:can_attack_los()  then
        return true
    end

    return self:range() > self:melee_range()
end

function Monster:is_ranged()
    return self:function_memo(self._is_ranged)
end

local fighter_monsters = util.set({
    "Agnes", "Asmodeus", "Antaeus", "ancient champion", "angel",
    "antique champion", "Asmodeus", "balrug", "centaur warrior", "Cerebov",
    "cherub", "daeva", "death knight", "deep elf blademaster",
    "deep elf knight", "demonspawn warmonger", "Dispater", "Donald", "Duvessa",
    "Edmund", "entropy weaver", "Executioner", "fire giant", "Frederick",
    "frost giant", "Geryon", "Gloorx Vloq", "gnoll sergeant", "guardian mummy",
    "Harold", "Head Instructor", "hell knight", "Ignacio", "iron giant",
    "jiangshi", "Jory", "Joseph", "juggernaut", "Lom Lobon", "Mennas",
    "minotaur", "Mnoleg", "naga warrior", "nagaraja", "nargun", "norris",
    "Orb Guardian", "orc knight", "orc warlord", "orc warrior",
    "phantasmal warrior", "profane servitor", "reaper", "red devil",
    "Saint Roka", "salamander", "seraph", "sin beast", "skeletal warrior",
    "Sojobo", "spriggan berserker", "spriggan defender", "spriggan rider",
    "tainted leviathan", "tengu reaver", "tengu warrior", "titan",
    "undying armoury", "Urug", "ushabti", "vampire knight", "vault guard",
    "vault sentinel", "vault warden", "war gargoyle", "Wiglaf",
    "yaktaur captain"
})
function Monster:_is_fighter()
    if self:type() == const.pan_lord_type then
        return true
    end

    local name = self:name()
    if name:find("draconian knight") or name:find("draconian monk") then
        return true
    end

    return fighter_monsters[name]
end

function Monster:is_fighter()
    return self:function_memo(self._is_fighter)
end

function Monster:_regains_los()
    if not self:is_ranged() or self:intelligence() ~= "Human" then
        return false
    end

    local name = self:name()
    return name == "centaur warrior"
        or name == "yaktaur captain"
        or not self:is_fighter()
end

function Monster:regains_los()
    return self:function_memo(self._regains_los)
end

function Monster:choose_firing_pos(pos)
    return self:function_memo_args(monster_choose_firing_pos, pos)
end

-- This function is for monsters that are safe but still block movement.
function Monster:_is_harmless()
    return self:is_firewood() or self:name() == "butterfly"
end

function Monster:is_harmless()
    return self:function_memo(self._is_harmless)
end

-- Whether we'd ever want to attack this monster, and hence whether it'll be
-- put in the enemy list.
function Monster:_is_enemy()
    if self:is_harmless() or self:name() == "orb of destruction" then
        return false
    end

    local attitude = self:attitude()
    return attitude < const.attitude.neutral
        or attitude == const.attitude.neutral and self:is("frenzied")
end

function Monster:is_enemy()
    return self:function_memo(self._is_enemy)
end

-- Whether the player can melee this monster right now.
function Monster:player_can_melee(ignore_temp)
    return self:function_memo_args(player_can_melee_mons, ignore_temp)
end

function Monster:_is_unalert()
    return self:is("sleeping") or self:is("dormant") or self:is("wandering")
end

function Monster:is_unalert()
    return self:function_memo(self._is_unalert)
end

function Monster:_can_move(ignore_temporary)
    if self:is_stationary()
            or self:name() == "wandering mushroom" then
        return false
    end

    if ignore_temporary then
        return true
    end

    return not (self:is_caught()
        or self:is_constricted()
        or self:status("paralysed")
        or self:status("confused")
        or self:status("petrified")
        or self:status("constricted by roots"))
end

function Monster:can_move(ignore_temporary)
    return self:function_memo_args(self._can_move, ignore_temporary)
end

function Monster:_player_can_swap()
    return self:attitude() > const.attitude.neutral and self:can_move()
end

function Monster:player_can_swap()
    return self:function_memo(self._player_can_swap)
end

function Monster:_can_seek(ignore_temporary)
    if self:name():find("vortex") then
        return false
    end

    return self:can_move(ignore_temporary)
        and (ignore_temporary or not (self:is_unalert() or self:is("fleeing")))
end

function Monster:can_seek(ignore_temporary)
    return self:function_memo_args(self._can_seek, ignore_temporary)
end

function Monster:_can_melee_at(pos)
    return positions_can_melee(self:pos(), pos, self:melee_range())
end

function Monster:can_melee_at(pos)
    return self:function_memo_args(self._can_melee_at, pos)
end

function Monster:can_melee_player()
    return self:can_melee_at(const.origin)
end

function Monster:_melee_square_function(dest_pos)
    return function(pos)
        if not self:can_traverse(pos) then
            return false
        end

        local mons = get_monster_at(pos)
        -- Other enemy monsters aren't considered to block our path, since they
        -- may swap...
        if mons and (not mons:is_enemy()
                -- except that enemies already to melee their target won't
                -- swap.
                or mons:can_melee_at(dest_pos)) then
            return false
        end

        return true
    end
end

function Monster:melee_square_function(dest_pos)
    return self:function_memo_args(self._melee_square_function, dest_pos)
end

--[[
Whether this monster could follow a path to melee the player.

@treturn boolean True if the monster has such a path, false otherwise.
]]--
function Monster:_melee_move_search(dest_pos, start_pos)
    if not self:can_seek(true) then
        return false
    end

    if not start_pos then
        start_pos = self:pos()
    end

    return move_search(start_pos, dest_pos, self:melee_square_function(dest_pos),
        self:melee_range())
end

function Monster:melee_move_search(dest_pos, start_pos)
    return self:function_memo_args(self._melee_move_search, dest_pos,
        start_pos)
end

function Monster:_melee_move_distance(pos)
    if self:can_melee_at(pos) then
        return 0
    end

    local result = self:melee_move_search(pos)
    if result then
        return result.dist
    else
        return const.inf_dist
    end
end

function Monster:melee_move_distance(pos)
    return self:function_memo_args(self._melee_move_distance, pos)
end

function Monster:has_line_of_fire(pos)
    return self:function_memo_args(monster_has_line_of_fire_at, pos)
end

--[[
Whether this monster can either currently melee the player or has a movement
path to do so.
]]--
function Monster:_has_path_to_melee_player()
    if self:can_melee_player() then
        return true
    end

    return self:melee_move_search(const.origin)
end

function Monster:has_path_to_melee_player()
    return self:function_memo(self._has_path_to_melee_player)
end

--[[
Whether this monster has a traversable path it can take to get adjacent to
the player. Does not consider any monsters that might currently block its
movement.
@treturn boolean True if the monster has such a path, false otherwise.
]]--
function Monster:_can_traverse_to_player()
    if position_distance(self:pos(), const.origin) == 1 then
        return true
    end

    if not self:can_seek(true) then
        return false
    end

    local function move_func(pos)
        return self:can_traverse(pos)
    end
    return move_search(self:pos(), const.origin, move_func, 1)
end

function Monster:can_traverse_to_player()
    return self:function_memo(self._can_traverse_to_player)
end

function Monster:_player_melee_range()
    return self:is("warding") and 1 or player_melee_range()
end

function Monster:player_melee_range()
    return self:function_memo(self._player_melee_range)
end

function Monster:_player_can_wait_for_melee()
    return not self:player_can_melee(true)
        and self:has_path_to_melee_player()
        and (self:melee_range() <= self:player_melee_range()
                or get_move_closer(self:pos()))
        and self:distance() > self:melee_range()
end

function Monster:player_can_wait_for_melee()
    return self:function_memo(self._player_can_wait_for_melee)
end

function Monster:_adjacent_cells_known()
    for pos in adjacent_iter(self:pos()) do
        if feature_at(pos) == "unseen" then
            return false
        end
    end
    return true
end

function Monster:adjacent_cells_known()
    return self:function_memo(self._adjacent_cells_known)
end

function Monster:should_dig_unreachable()
    return self:function_memo(should_dig_unreachable_monster)
end

function Monster:_is(flag)
    return self.minfo:is(flag)
end

function Monster:is(flag)
    return self:function_memo_args(self._is, flag)
end

function Monster:_status(status)
    return self.minfo:status(status)
end

function Monster:status(status)
    return self:function_memo_args(self._status, status)
end

function Monster:_player_has_path_to_melee(allow_unsafe)
    if self:player_can_melee(true) then
        return true
    end

    local move_type = allow_unsafe and const.move.traversable
        or const.move.safe
    return move_path(move_type, self:map_pos(), self:player_melee_range())
end

function Monster:player_has_path_to_melee(allow_unsafe)
    return self:function_memo_args(self._player_has_path_to_melee,
        allow_unsafe)
end

function Monster:weapon_accuracy(item)
    local str = self.minfo:target_weapon(item)
    str = str:gsub(".-(%d+)%% to hit.*", "%1")
    return tonumber(str) / 100
end

function Monster:throw_accuracy(item)
    local str = self.minfo:target_throw(item)
    str = str:gsub(".-(%d+)%% to hit.*", "%1")
    return tonumber(str) / 100
end

function Monster:evoke_accuracy(item)
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
end
