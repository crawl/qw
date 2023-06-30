# Debugging

qw has some basic debug output functionality. Note that currently, most of its
internal variables are local and are not accessible directly. All of its
functions are global, however, and can be run normally via the clua console.

## Debugging rc variables

This variables should be configured in the qw rc file.

* `DEBUG_MODE`

  Set to `true` to enable debug mode by default. Debug mode causes debug
  messages to be printed according to the enabled channels defined in
` DEBUG_CHANNELS`.

* `DEBUG_CHANNELS`

  A list of debug channel names that will have debugging messages printed when
  debug mode is enabled. The available channels are:

  + "combat": Melee targeting and combat.
  + "explore": Map exploration and feature discovery.
  + "flee": Updates to the flee position.
  + "map": Updates to the map data cache and distance maps
  + "plans": Plan execution results. This generates a lot of output.
  + "ranged": Ranged targeting and combat.
  + "skills": Skill selection.
  + "throttle": Throttling and memory usage.

* `SINGLE_STEP`

  Set to `true` to have qw take one action at a time with the *Tab* key.

* `WIZMODE_DEATH`

  Set to `true` to have qw accept death if it loses all HP in Wizard Mode. By
  default it keeps playing.

## Debugging functions

These can be executed from the clua console or inserted into qw's code.

* `override_goal(goal)`

  Have qw attempt the goal given in `goal`. Here `goal` is a string giving a
  single goal in the format describe in [README.md#goals].

* `dsay(x)`

  Say `x` the message log, converting `x` to a string. This conversion works
  on tables and prints a nested representation of the table contents. Functions
  and userdata object can't be converted.

* `toggle_debug()`

  Enable or disable debug mode. qw's internal debugging messages are never
  printed when debug mode is disabled, regardless of which debug channels are
  enabled.

* `toggle_debug_channel(channel)`

  Enable or disable output for the debug channel named `channel` (string).

* `debug_channel(channel)`

  Returns true if the given debug channel is enabled. Use this when adding
  permanent debugging statements to condition printing the message on whether
  the corresponding debug channel is enabled. For performance reasons, any code
  involving complicated string creation or additional calculations that would
  execute frequently should be conditional on the results of a call to
  `debug_channel()`.

* `print_traversal_map(center)` and `print_unexclusion_map(center`

  Print 20 squares from the position `center`of the traversal or unexclusion
  map. In these maps, `.` represents traversable/unexcluded, `#` represents
  untraversable/excluded, and `nil` means the position is still unseen. The
  player, if within 20 squares of `center`, is represented by `@`, `7`, or `✞`
  if the player's position is traversable/unexcluded, untraversable/excluded,
  or `nil`, respectively. The center itself is represented by `&`, `8`, or `W`
  for the same corresponding map states.

* `print_distance_maps(center, excluded)`
  and `print_distance_map(dist_map, center, excluded)`

  Print 20 squares from the position `center` of all distance maps or the given
  distance map. If `excluded` is true, print the exclusion-aware distance map,
  otherwise print the map that ignores exclusions. Distances for traversable
  squares are shown as ASCII symbols based on the distance, starting with `A`
  represent 0. For distances from 61 to 180, a `Ø` is shown, and for distances
  above 180, `∞` is shown. The player and center positions are represented the
  same way as for `print_traversal_map()`.

* `toggle_throttle()`

  Enable or disable the use of the coroutine to break up longer calculations by
  sending non-operational input.

* `reset_coroutine()` and `resume_qw()`

  If qw has errored, use `reset_coroutine()` to delete the current coroutine.
  Use `resume_qw()` to tell qw to resume execution.

## Miscellaneous tips for coding and testing

* You can run qw with the DCSS command-line option -seed <n> to use a seeded
  RNG for (relatively) reproducible testing.

* qw outputs its version string and current configuration as notes at the start
  of every game. These can be viewed from the in-progress game dump and the
  final game morgue. The version string is updated by the `make-qw.sh` script
  based on `git describe`.