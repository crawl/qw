------------------------
-- Global variables. This file declares shared variables as local to the scope
-- of the final qw lua source file.

-- The version of qw for logging purposes. Run the make-qw.sh script to set
-- this variable automatically based on the latest annotated git tag and
-- commit, or change it here to a custom version string.
local qw_version = "%VERSION%"

-- Crawl enum values :/
local enum_mons_pan_lord = 344
local enum_att_friendly = 4
local enum_att_neutral = 1

-- Constants
local MAX_MEMORY
local INF_TURNS
local INF_DIST
local GXM
local origin
local RUNE_SUFFIX
local ORB_NAME
local MAX_TEMP_DISTANCE_MAPS

-- Enum tables
local AUTOEXP
local FEAT_LOS
local DIR

-- Plan functions. These must later be initialized as cascades.
local plan_emergency
local plan_exclusion
local plan_attack
local plan_rest
local plan_handle_acquirement_result
local plan_pre_explore
local plan_pre_explore2
local plan_explore
local plan_explore2
local plan_stuck
local plan_move

-- All variables past this point are qw state.
local initialized = false
local debug_mode = false
local branch_data = {}
local hell_branches
local portal_data = {}
local god_data = {}
local good_gods
local upstairs_features
local downstairs_features

local debug_channels = {}

local coroutine_throttle = true
local memory_limit
local abort_qw = false
local automatic = false
local update_coroutine
local do_dummy_action
local dump_count = you.turns() + 100 - (you.turns() % 100)
local skill_count = you.turns() - (you.turns() % 5)
local have_message = false
local read_message = true
local restart_cascade = false

local gameplan_list
local which_gameplan = 1
local debug_gameplan
local gameplan_status
local gameplan_branch
local gameplan_depth
local gameplan_travel
local want_gameplan_update

local early_first_lair_branch
local first_lair_branch_end
local early_second_lair_branch
local second_lair_branch_end
local early_vaults
local vaults_end
local early_zot
local zot_end
local abyssal_rune

local planning_god_uses_mp
local planning_good_god
local planning_tso
local planning_vaults
local planning_slime
local planning_pan
local planning_undead_demon_branches
local planning_cocytus
local planning_gehenna
local planning_zig

local previous_where
local where
local where_branch
local where_depth

local base_corrosion
local permanent_flight
local gained_permanent_flight
local temporary_flight
local can_retreat_upstairs
local open_runed_doors
local permanent_bazaar
local dislike_pan_level = false

local cache_parity
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

local global_pos = {}
local flee_positions
local reachable_position
local target_flee_position
local last_flee_turn = -100

local turn_count = you.turns() - 1
local time_passed
local memos

local los_radius
local have_orb
local disable_autoexplore
local last_wait = 0
local wait_count = 0
local hiding_turn_count = -100

local prev_hatch_dist = 1000
local prev_hatch

local monster_map
local enemy_list
local danger
local immediate_danger

local ignore_traps
local stairs_travel
local position_is_safe
local position_is_cloudy
local incoming_melee_turn = -1
local full_hp_turn = 0

local next_delay = 100
local is_waiting

local invis_monster = false
local invis_monster_pos
local invis_monster_turns = 0
local nasty_invis_caster = false

local hostile_summon_timer = -200

local enemy_memory
local turns_left_moving_towards_enemy = 0

local stuck_turns = 0
local move_destination
local move_reason

local upgrade_phase = false
local acquirement_pickup = false
local acquirement_class

local tactical_step
local tactical_reason

local stairdance_count = {}
local clear_exclusion_count = {}
local vaults_end_entry_turn
local tomb2_entry_turn
local tomb3_entry_turn

local last_swamp_fail_count = -1
local swamp_rune_reachable = false

local last_min_delay_skill = 18

local only_linear_resists = false

local no_spells = false
