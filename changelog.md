# Changelog

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
