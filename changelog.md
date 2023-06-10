# Changelog

## 0.2.0 (2023-06-16)

This version supports DCSS 0.30.

### Release Highlights

* Support for ranged combat with launchers.
* Greatly improved within-level pathing.
* Use of exclusions for unreachable monsters.

### Configuration and Performance
* The default 15-rune route now attempts Slime before converting to TSO.
* The `Orb` goal now only has qw seek and pick up the Orb of Zot. This can be
  used with subsequent non-winning goals to do challenges like Orb run Tomb.
* A new `Escape` goal that has qw exit on D:1 (regardless of having the Orb).
* A new `Win` goal that executes the `Orb` goal followed by `Escape`. This goal
  is always selected when the end of the goal list is reached.
* qw assumes 32MB of max memory available to lua and will halt execution if 90%
  of this limit is reached. Crawl has a new `-lua-max-memory` argument that
  should be used to increase the memory available to clua to at least 32MB.
* A `COROUTINE_THROTTLE` variable to enable or disable use of yielding to
  break up cpu-intensive calculations.
* Crawl should be run with the `-no-throttle` argument for WebTiles or
  dgamelaunch servers, since we can't guarantee that qw won't trigger crawl's
  lua throttle even if qw's coroutine throttle is enabled.
* Gameplans are now referred to as goals in both documentation and code.

### Debug
* New functions `reset_coroutine()` and `resume_qw()` to aid in debugging when
  qw halts due to an error.
* An `override_goal()` function to set which has qw attempt the specified goal.
* New functions `print_traversal_map()`, `print_unexcluded_map()`,
  `print_distance_maps()`, and `print_distance_map()` to display sections of
  map data in the message log.

### Exploration and Map
* Use of distance mapping to navigate many previously unsolveable pathing
  situations:
  + Unreachable monsters without`los_no_trans` that still prevent resting or
    autoexplore.
  + Unreachable monsters with `los_no_trans` that we can't move to and that
    can't move to us.
  + Unreachable travel destinations due to firewood monsters blocking the path.
  + Moving towards unexplored areas to satisfy exploration goals when
    autoexplore is unable to reach these areas.
* Use of exclusions for unreachable monsters:
  + Unreachable monsters we can't attack with ranged.
  + Unreachable monsters that get us to low HP while we try to use ranged
    attacks.
  + Consider whether we have digging and want to dig out a currently
    unreachable monster instead of excluding it.
  + Move past excluded monsters to the next feature we need to take for travel
    purposes.
  + Mark excluded stairs in exclusions as unsafe. Don't stairdance up a
    staircase if its destination staircase is unsafe.
* Move towards the abyssal runelights to help find the abyssal rune.
* Move towards the abyssal rune even with hostiles around if HP is not low.
* The Orb run and Abyss are handled in what is now the single move plan list.
  This allows attempting non-Win goals after the Orb has been obtained, e.g.
  Orbrun Tomb.
* Waypoints are used on every level, allowing execution of plans that use
  distance mapping in the Abyss, Pan, and in portals.
* Monster pathing checks now considers each monster's specific traversal
  abilities.
* qw can recover from missing `c_persist` data and will visit any levels as
  necessary to re-record data.

### Items and Equipment
* Assessment and use of launcher weapons for characters that start with one.
* Dex and Str from items are valued according to which stat qw's weapon uses.
* On weapons, value the spectral brand twice as much and the electrocution
  brand half as much. The new heavy brand is valued 33% more than
  flaming/freezing.
* More accurately keep currently unfavorable items based on future goals:
  + Items that won't be disliked by future gods.
  + Items that don't remove availability of MP required for future gods.
* Correct evaluation of future god MP requirements for items.
* Evaluation of Str and Dex based on which stat our weapon uses.

### Strategy and Tactics
* Targeting for throwing and launchers that chooses the best enemy based on
  relevant criteria like distance, threat, damage level, etc.
* A new tatical step that tries to move away from slimy walls.
* The water movement tactical step can activate if we have a ranged target even
  if we have no adjacent enemies.

## 0.1.0 (2022-09-16)

This is the first tagged release of qw. Each future release will coincide with
a new version of DCSS that qw supports; this release supports DCSS 0.29. The
0.1.0 changelog covers the major changes to qw since DCSS 0.28.

### Release Highlights

* Configurable game planning that handles all in-game goals.
* Greatly improved travel and exploration.
* Support for Gauntlet and WizLabs.
* Support for Ignis and Cinder Acolytes.

### Backgrounds and Species
* Cinder Acolyte support.
* Zealots don't need to specify their starting god in their god list. They
  never attempt to change gods unless the gameplan list explicitly requests it.
* Chaos Knights abandon Xom according to the new `CK_ABANDONS_XOM` variable,
  which defaults to true.
* Ghouls now prefer axes, and Ogres no longer prefer maces.

### Branches
* Support for Gauntlet and WizLab portals. These and the Desolation portal are
  now done by default.
* Improved tactics for Tomb that use potions of hasting, attraction, and magic
  for Tomb:2 and Tomb:3 ambushes.
* Use potions of might and haste and scrolls of teleport when facing many
  dangerous monsters in Hell branches.
* Handle the case when permanent teleport/dispersal traps block both paths
  deeper into the Zot:5 vault. Conditionally enable attempting to walk into
  these traps until we're able to continue autoexplore.
* Portal tracking that allows transitioning into and out of the plan to enter a
  portal based on level messages and time passed.
* Collect and use ziggurat figurines when the gameplan list requests visiting a
  Zig.

### Configuration
* Support for a game planning syntax:
  - Each gameplan specifies a branch, level range, rune, god conversion,
    shopping, or getting the Orb.
  - Gameplans are grouped into lists defined in the new `GAMEPLANS` rcfile
    variable, with the `DEFAULT_GAMEPLAN` variable specifying the active list.
    The gameplans of the active list be achieved in sequence.
* The `COMBO_CYCLE_LIST` syntax allows specifying a gameplan list on a
  per-combo basis.
* The set of allowed portals is specified in the new `ALLOWED_PORTALS` rcfile
  variable.
* qw's version and basic configuration are noted in the note log at game start.

### Exploration and Travel
* Travel and exploration systems rewritten:
  - Travel between levels and branches proceeds directly to the desired
    destination instead of first requiring travel to the end of any parent
    branch.
  - Stair finding and exploration is explicitly tracked, with a level being
    considered explored only when any generated up and down stone stairs have
    been seen and are reachable.
  - A stair exploration process allows qw to try unexplored stairs in order to
    find any missing stairs.
  - Due to precise tracking of autoexplore and stair exploration state, qw is
    far more capable of continuing exploration instead of getting stuck in
    disconnected areas.
* Transporter usage in portals, Pan, and the Abyss.

### Gods
* Ignis support:
  - Use fiery armour based on current HP and scary/nasty monster presence.
  - The normal plan converts to a god in our god list when piety drops below
    1\*.
* Use Ru's apocalypse more aggressively.
* Prefer Ru sacrifices by how much piety they're worth.
* Use TSO's cleansing flame ability aggressively.
* Revised "scary" and "nasty" monster lists used for god abilities that
  incorporates new monsters and adjusts existing monsters based on observed qw
  death counts.

### Strategy and Tactics
* Added assessment for more weapon and armour egos and amulet types and such
  that all assessments apply to both mundane and artefact items.
* Use throwing at the default throwing target based on availability of non-dart
  projectiles. Train Throwing skill with appropriate utility based on available
  ammo.
* Shield skill utility calculations updated for the current shield penalty
  system.
* Collect potions of cancellation and use them when in danger and polymorphed
  into a bad form.
* Use might and haste for Cerebov.
