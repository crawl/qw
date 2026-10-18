------------------------
-- Global variables and functions that need early definition.
-- This file declares shared variables as local to the scope of
-- the final qw lua source file.

-- The main qw table.
qw = {}

local branch_data = {}
local hell_branches
local portal_data = {}
local god_data = {}
local good_gods

local goal_list
local which_goal = 1
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

local permanent_bazaar
local dislike_pan_level = false

local transp_map = {}
local transp_search_zone
local transp_search_count
local transp_zone
local transp_orient
local transp_search

local disable_autoexplore
local hiding_turn_count = -100

local prev_hatch_dist = 1000
local prev_hatch

local stairs_travel

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

-- Define a table of enum values.
function enum(tbl)
    local e = {}
    for i, val in ipairs(tbl) do
        e[val] = i - 1
    end

    return e
end

-- All constants go in this table.
const = {}

-- Maximum map width. We use this as a general map radius that's guaranteed to
-- reach the entire map, since qw is never given absolute coordinates by crawl.
-- This constant must be defined before new_position() is ever called.
const.gxm = 80

function hash_coords(x, y)
    return 2 * const.gxm * x + y
end

function new_position(x, y)
    -- Some callers might pass nil coordinates returned from e.g. from the clua
    -- api. Return nil instead of asserting or erroring when trying to hash.
    if not x or not y then
        return
    end

    return { x = x, y = y, hash = hash_coords(x, y) }
end

-- Plan functions. These must later be initialized as cascades.
local plans = {}
