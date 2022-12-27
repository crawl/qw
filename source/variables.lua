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
local enum_gxm

-- Enum tables and constants
local AUTOEXP
local FEAT_LOS
local DIR
local INF_TURNS

-- All variables past this point are qw state.
local initialized = false
local branch_data = {}
local hell_branches
local portal_data = {}
local god_data = {}
local good_gods
local upstairs_features
local downstairs_features

local time_passed
local automatic = false
local update_coroutine
local do_dummy_action
local dump_count = you.turns() + 100 - (you.turns() % 100)
local skill_count = you.turns() - (you.turns() % 5)
local have_message = false
local read_message = true

local gameplan_list
local override_gameplans
local which_gameplan = 1
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

local los_radius
local base_corrosion
local disable_autoexplore
local level_has_upstairs
local base_corrosion
local open_runed_doors
local permanent_bazaar
local ignore_traps
local dislike_pan_level = false

local branch_step_mode = false
local stepped_on_lair = false
local stepped_on_tomb = false

local stairs_travel
local danger
local immediate_danger
local cloudy

local ignore_list = { }
local failed_move = { }
local invisi_count = 0
local next_delay = 100
local is_waiting

local sigmund_dx = 0
local sigmund_dy = 0
local invis_sigmund = false

local greater_servant_timer = -200

local stuck_turns = 0

local did_move = false
local move_count = 0

local did_move_towards_monster = 0
local target_memory_x
local target_memory_y

local last_wait = 0
local wait_count = 0
local old_turn_count = you.turns() - 1
local hiding_turn_count = -100

local monster_array
local enemy_list

local upgrade_phase = false
local acquirement_pickup = false
local acquirement_class

local tactical_step
local tactical_reason

local go_travel_attempts = 0
local stash_travel_attempts = 0

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

local waypoint_parity
local feature_searches
local feature_positions
local traversal_maps
local distance_maps
local good_stairs
local target_stair
local last_flee_turn = -100

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

local prev_hatch_dist = 1000
local prev_hatch_x
local prev_hatch_y

local plan_abyss_rest
local plan_abyss_move

local plan_emergency
local plan_rest
local plan_handle_acquirement_result
local plan_pre_explore
local plan_pre_explore2
local plan_explore
local plan_explore2
local plan_move

local plan_orbrun_rest
local plan_orbrun_emergency
local plan_orbrun_move
