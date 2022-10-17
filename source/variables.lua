------------------------
-- Some global (local) variables and function
-- This code must be at the top of the final lua source file.

-- The version of qw for logging purposes. Run the make-qw-rc.sh script to set
-- this variable automatically based on the latest annotate git tag and commit,
-- or change it here to a custom version string.
local qw_version = "%VERSION%"

-- Crawl enum values :/
local enum_mons_pan_lord = 344
local enum_att_friendly = 4
local enum_att_neutral = 1

-- Enum tables
local AUTOEXP
local FEAT_LOS
local DIR
local INF_TURNS = 200000000

local initialized = false
local time_passed
local automatic = false
local update_coroutine
local do_dummy_action

local branch_data = {}
local hell_branches
local portal_data = {}
local god_data = {}
local good_gods

local where
local where_branch
local where_depth
local can_waypoint
local los_radius
local base_corrosion

local dump_count = you.turns() + 100 - (you.turns() % 100)
local skill_count = you.turns() - (you.turns() % 5)

local early_first_lair_branch
local first_lair_branch_end
local early_second_lair_branch
local second_lair_branch_end
local early_vaults
local vaults_end
local early_zot
local zot_end

local gameplan_list
local override_gameplans
local which_gameplan = 1
local gameplan_status
local gameplan_branch
local gameplan_depth
local permanent_bazaar
local ignore_traps

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

local travel_branch
local travel_depth
local want_gameplan_update
local want_go_travel
local disable_autoexplore

local stairs_search_dir
local stairs_travel

local go_travel_attempts = 0
local stash_travel_attempts = 0

local transp_search
local transp_zone
local zone_counts = {}

local danger
local immediate_danger
local cloudy

local ignore_list = { }
local failed_move = { }
local invisi_count = 0
local next_delay = 100

local sigmund_dx = 0
local sigmund_dy = 0
local invis_sigmund = false

local sgd_timer = -200

local stuck_turns = 0

local stepped_on_lair = false
local stepped_on_tomb = false
local branch_step_mode = false

local did_move = false
local move_count = 0

local did_move_towards_monster = 0
local target_memory_x
local target_memory_y

local last_wait = 0
local wait_count = 0
local old_turn_count = you.turns() - 1
local hiding_turn_count = -100

local have_message = false
local read_message = true

local monster_array
local enemy_list

local upgrade_phase = false
local acquirement_pickup = false
local acquirement_class

local tactical_step
local tactical_reason

local is_waiting

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

local traversal_map
local stair_dists
local waypoint_parity
local good_stair_list
local target_stair
local last_flee_turn = -100

local map_mode_search
local map_mode_search_key
local map_mode_search_pos
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
