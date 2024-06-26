------------------------
-- Global variables. This file declares shared variables as local to the scope
-- of the final qw lua source file.

-- All constants go in this table.
local const = {}

-- Plan functions. These must later be initialized as cascades.
local plans = {}

-- All variables past this point are qw state.
local qw = {}

local branch_data = {}
local hell_branches
local portal_data = {}
local god_data = {}
local good_gods

local goal_list
local which_goal = 1
local debug_goal
local goal_status
local goal_branch
local goal_depth
local goal_travel

local early_first_lair_branch
local first_lair_branch_end
local early_second_lair_branch
local second_lair_branch_end
local early_vaults
local vaults_end
local early_zot
local zot_end

local previous_god
local previous_where
local where
local where_branch
local where_depth

local permanent_flight
local gained_permanent_flight
local temporary_flight
local open_runed_doors
local permanent_bazaar
local dislike_pan_level = false

local cache_parity
local check_reachable_features = {}
local feature_map_positions_cache
local feature_map_positions
local item_searches
local item_map_positions_cache
local item_map_positions
local traversal_maps_cache
local traversal_map
local exclusion_maps_cache
local exclusion_map
local distance_maps_cache
local distance_maps

local level_map_mode_searches
local map_mode_searches
local map_mode_search_key
local map_mode_search_hash
local map_mode_search_zone
local map_mode_search_count
local map_mode_search_attempts = 0

local transp_map = {}
local transp_search_zone
local transp_search_count
local transp_zone
local transp_orient
local transp_search

local disable_autoexplore
local last_wait = 0
local wait_count = 0
local hiding_turn_count = -100

local prev_hatch_dist = 1000
local prev_hatch

local stairs_travel

local next_delay = 100

local invis_monster = false
local invis_monster_pos
local invis_monster_turns = 0
local nasty_invis_caster = false

local hostile_summon_timer = -200

local stairdance_count = {}
local clear_exclusion_count = {}
local vaults_end_entry_turn
local tomb2_entry_turn
local tomb3_entry_turn
