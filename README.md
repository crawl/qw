# qw

This rcfile is elliptic's DCSS bot "qw", the first bot to win DCSS with no
human assistance. A substantial amount of code here was contributed by elliott
or borrowed from N78291's bot "xw", and many others have contributed as well.
The bot is now maintained by the DCSS devteam. Please post bug reports as
issues on the official crawl qw repository:

https://github.com/crawl/qw/issues/new

qw can play most species and background combinations in a melee-focused way and
has some basic grasp of how many gods work. Note though that most spells and
racial abilities aren't used, and qw is not very good! It has won games with 3
and 15 runes, and we try to maintain qw so it can continue to play and win the
current version. See [accomplishments.md](accomplishments.md) for current and
past achievements.

## Running qw

To run qw, you'll need a local trunk build of crawl, or your own crawl WebTiles
server with this build availabe.

### Setting up an rcfile

First clone this repository, and then make any desired changes to the
configuration in [qw.rc](qw.rc). See the comments in this file and the
[configuration](#configuration) section below for more details. Next, use the
[make-qw.sh](make-qw.sh) script from this repository to combine all lua source
files in one of two ways.

#### Method 1: lua include file (recommended)

This puts all source lua into a single `qw.lua` file that gets included into the rcfile via an `include` statement.

Steps:
* Run `make-qw.sh` to create `qw.lua`.
* Uncomment the include line at the end of qw.rc so that it simply reads
  ```
  include = qw.lua
  ```
* To run qw locally use a command like:
  ```bash
  ./crawl -rc /path/to/qw/qw.rc -rcdir /path/to/qw
  ```
  The `-rcdir` option is necessary for crawl to find qw.lua.

This method makes rcfile modifications easier and debugging easier due to line
numbers from error messages.Note that when running qw on a server, you can
still use this method if you use the `qw.lua` file as the rcfile contents of
another account. You would then modify your `include = qw.lua` statement to be
`include = ACCOUNT.rc` where `ACCOUNT` is the second account name.

#### Method 2: lua directly in the rcfile

This puts all lua directly into the rcfile. This is an easy way to run qw from
a single account on an online server.

Steps:
* Run `make-qw.sh -r qw.rc` to inline all lua directly into the contents of
  `qw.rc`, saving the results in `qw-final.rc`.
* To run qw locally use a command like:
  ```bash
  ./crawl -rc /path/to/qw/qw-final.rc
  ```

Note that `make-qw.sh` looks for a marker in `qw.rc` to know where to insert
the lua. This is `# include = qw.lua` by default.

### Starting qw after crawl is loaded

Enter a name if necessary and start a game. If you didn't change the
`AUTO_START` variable, the "Tab" key will start and stop qw.

The file [qw.exp](qw.exp) is a simple expect script that automates running qw
for many games in a row. The `AUTO_START` variable should be left at false when
when using this. (With minor modifications, this can also be used to run games
on a remote server over ssh.)

### Running on a WebTiles server

It's best to run qw either locally or on your own crawl server. You can set up
[Sequell](https://github.com/crawl/sequell) or the DCSS
[scoring](https://github.com/crawl/scoring) scripts to track statistics from
local games.

Please don't run qw on an official server unless you have permission from the
server admin. Misconfigured (or even well-configured) bots can eat up server
CPU from actual players. If you do have permission from your server admin,
server please add the name of the account that you are using for qw to the
Sequell "bot" nick with `!nick bot <accountname>` so that games on the account
can be easily filtered out of queries. Also, please don't run qw on the same
account that you use for your own personal games.

Steps:
* Follow the [instructions above](#setting-up-an-rcfile) to create a final
  rcfile based on your modified `qw.rc`. If you need to use only a single
  account, you'll want [Method 2](method-2:-lua-directly-in-the-rcfile), but
  the first method works if you can use two accounts.
* In a text editor, open your qw.rc file.
* In the *Interface* section, on the lines with `: DELAYED = false` and `:
  AUTO_START = false`, change `false` to `true`
* Click the "(edit rc)" link for DCSS trunk and paste the full contents of the
  final rcfile, and click Save.
* Run DCSS trunk, either in WebTiles or in console. If you didn't change the
  `AUTO_START` variable to `true`, press "Tab".

Since clua works on the server side, WebTiles drawing can lag behind things
actually happening. To see more current events just refresh the page and press
"Tab". Alternatively, run or watch the bot in console (via ssh).

## Configuration

Most qw variables are straightforward and are described in in comments in
qw.rc. Some important and more complicated variables are described here. Note
that lines in qw.rc beginning with `:` define Lua variables and must be valid
Lua code, otherwise the lines are Crawl options as described in the [options
guide](https://github.com/crawl/crawl/blob/master/crawl-ref/docs/options_guide.txt).

### Combos and Gods

To have qw play one type of char or select randomly from a set of combos, use
the `combo` rcfile option. See comments in the rcfile for examples. Then change
the `GOD_LIST` variable to set the gods qw is allowed to worship. Each entry
in `GOD_LIST` can be the full god name, as reported by `you.god()`, or the
abbreviation made with the first 1, 3, or 4 letters of the god's name with any
whitespace removed. For *the Shining One*, you can use the abbreviations "1" or
"TSO". For *No God*, you can use the abbreviations "0" or "None". For
non-zealots, qw will worship the first god in the list it finds, entering
Temple if it needs to. To have CK abandon Xom immediately, set `CK_ABANDON_XOM`
to `true`, otherwise all zealots will remain with their starting god unless
told to convert explicitly by the [gameplan list](#game-plans).

Gods who have at least partly implemented are *BCHLMOQRTUXY1*. Currently qw has
the most success with *Okawaru*, *Trog*, and *Ru*, roughly in that order. For
combos, GrFi, GrBe, MiFi, and MiBe are most successful.

#### Combo cycles

To have qw cycle through a set of combos, set `COMBO_CYCLE` to `true` and edit
`COMBO_CYCLE_LIST`. This list uses the same syntax as the `combo` option, but
with an optional `^<god initials>` suffix. The set of letters in `<god
initials>` gives the set of gods qw is allowed to worship for that combo.
Additionally, after this god list, you can specify a gameplan name from
`GAMEPLANS` with a `!<plan>` suffix. For example, the default list:

```lua
COMBO_CYCLE_LIST = "GrBe.handaxe, MiFi.waraxe^OR, GrFi.waraxe^O!15 Runes"
```

has qw cycle through GrBe, MiFi of either Okawaru or Ru, and GrFi of Okawaru
attempting the 15 runes plan.

### Gameplans

The `GAMEPLANS` variable defines a table of strings defining sets of gameplans
for qw to complete in sequence. Each key in this table is a descriptive string
that can be used in the `DEFAULT_GAMEPLAN` variable or in the
`COMBO_CYCLE_LIST` variable above to have qw execute that set of gameplans. The
entries in `GAMEPLANS` are case-insensitive, comma-separated strings of
*gameplans* that qw will follow in sequence.

The default gameplan is `Normal`, which is a meta gameplan that has qw proceed
through a 3-rune route that gives qw good success. This is mostly equivalent
to the following gameplan list:

```
"D:1-11, Lair, D:12-D:15, Orc, 1stLairBranch:1-3, 2ndLairBranch:1-3,
1stLairBranch:4, Vaults:1-4, 2ndLairBranch:4, Depths, Vaults:5, Shopping,
Zot:1-4, Orb"
```

Here `1stLairBranch` and `2ndLairBranch` refer to whatever Lair branches are
selected according to the `RUNE_PREFERENCE` rcfile variable. The other
differences between the above list and `Normal` are that qw enters Lair as soon
as it has sufficient piety for its god (see the `ready_for_lair()` function)
and that this route is subject to the rcfile variables `LATE_ORC` and
`EARLY_SECOND_RUNE`.

If `Normal` is followed by additional entries in the gameplan list, qw will
proceed to those after its `Shopping` gameplan is complete. Hence a viable 15
Rune route could be expressed as:

```
"Normal, God:TSO, Crypt, Tomb, Pan, Slime, Hells, Abyss, Zot"
```

This will have qw abandon its current god for the Shining One after shopping is
complete before heading through Crypt, Tomb, and the other extended branches.

The other types of gameplan entries are:

* `<branch>`

  Where `<branch>` is the branch name reported by `you.where()`. qw will fully
  explore all levels in sequence in that branch as well as get any branch
  runes before proceeding to the next gameplan.

  Examples: `D`, `Lair`, `Vaults`

* `<branch>:<range>`

  The <range> can be a single level or a range of levels separated with a dash.
  The levels in this range are fully explored in sequence, although qw will
  potentially explore just outside of the level range to find all stairs for
  levels in the range. If the range includes a level with a rune, qw will find
  this rune before considering the gameplan complete.

  Examples: `D:1-11`, `Swamp:1-3`, `Vaults:5`

* `Rune:<branch>`

  Go directly to the end level of `<branch>` and explore until the rune is
  obtained. This does not require full exploration of the level containing the
  rune.

  Examples: `Rune:Swamp`, `Rune:Vaults`, `Rune:Geh`

* `Shopping`

  Try to buy the items on qw's shopping list.

* `God:<god>`

  Abandon any current god and convert to `<god>`. This is useful for attempting
  extended branches where a different god would be sufficiently better that it's
  worth the risk of dying to god wrath. The name `<god>` can be the full god
  name as reported by `you.god()` or the abbreviation made by the first 1, 3, or
  4 letters of the god's name with any whitespace removed. For the Shining One,
  `TSO` and `1` are valid abbreviations. For No God, `No God`, `None`, and `0`
  are valid entries.

  Examples: `God:Okawaru`, `God:Oka`, or `God:O`; `God:TSO`, `God:Chei`

* `Orb`

  Pick up the Orb of Zot, go to D:1, and win. qw always switches to this plan
  when it completes all entries in its gameplan list. Note the `Orb` gameplan has
  qw dive through all levels of Zot to look for the orb on Zot:5. Proceed this
  plan with e.g. `Zot:1-4` or `Zot` if you want to explore more of the Zot
  branch.

* `Zig`, or `Zig:<num>`

  Enter a ziggurat, clear it through level `<num>`, and exit. If `<num>` is not
  specified, qw clears the entire ziggurat.

* `Hells`

  Do Hell and the 4 Hell branches in random order.

#### Some notes about exploration

qw considers a level explored if it's been autoexplored to completion at least
once, all its required stone upstairs and downstairs are reachable, and any
rune on the level has been obtained. Other types of unreachable areas,
transporters, and runed doors don't prevent qw from considering a level
autoexplored. In portals, the Abyss, and Pan, qw always opens all runed doors
and explores all transporters. If qw must travel through unexplored levels that
aren't part of its current gameplan, it will explore only as much as necessary
to find the necessary stairs and then take them. This behaviour includes
situations like being shafted.

For Hell branches, gameplans like `Rune:Geh`, `Rune:Tar`, etc. are good
choices, since they have qw dive to and get the rune while exploring as little
as possible of the final level. For a branch like Slime, a gameplan of
`Slime:5` is better, since it makes qw dive through Slime but explore Slime:5
fully to obtain the loot after the Royal Jelly is dead.

## Debugging

qw has some basic debug output functionality.

### Debugging variables

* `DEBUG_MODE`

  Set to `true` to enable debugging output.

* `DEBUG_CHANNELS`

  A list of debug channel names to output. The available channels are "main",
  the default for debug messages, "plans", which shows all plan execution and
  results (very spammy), "explore", which shows gameplan, travel, and
  exploration info, and "skills", which shows information about skill
  selection.

* `SINGLE_STEP`

  Set to `true` to have qw take one action at a time with the *Tab* key.

* `WIZMODE_DEATH`

  Set to `true` to have qw accept death if it loses all HP in Wizard Mode. By
  default it keeps playing.

### Debugging functions

Useful when logging into your qw account to diagnose problems. These can be
executed from the clua console.

* `dsay(str, channel)`

  Say `str` in debug channel `channel` (default "main") if debug mode is
  enabled. When adding permanent debugging statements, for performance reasons,
  any code involving complicated string creation or additional calculations
  that would execute every turn should be conditional on `DEBUG_MODE`, for
  performance reasons:

  ```lua
  if DEBUG_MODE then
      ...
      dsay(...)
  end
  ```

  Note that not doing this can impact performance even with debug mode
  disabled, since any code in the argument to `dsay()` is executed regardless.

* `toggle_debug()`

  Enable debug mode (i.e. toggle the `DEBUG_MODE` variable).

* `toggle_debug_channel(channel)`

  Toggle the output for the channel name in the `channel` string argument.

* `set_stairs(branch, depth, dir, feat_los)`

  Set `c_persist` stair knowledge for all stairs on the level of the direction
  given in `dir` to the LOS value in `feat_los`. For `dir`, 1 means downstairs,
  -1 meaning upstairs, and 0 means both. For `feat_los`, 0 means the stair hasn't
  been seen, 1 means seen but behind transparent wall, 2 means seen but behind a
  grate, 3 means reachable, and 4 means the stair has been used at least once.

### Miscellaneous tips for coding and testing

* Run qw locally with the DCSS command-line option -seed <n> to use a seeded
  RNG for (mostly) reproducible testing.

* Put code you want to test in the `ttt()` function on the bottom; make it run
  by macroing some key to `===ttt`.

* The `make-qw.sh` script has the following options to change
  base rcfile you've made from qw.rc with your desired settings and your qw.lua
  file. This script sets a custom version string variable based on the latest
  git annotated tag and commit.

* qw outputs its version string and current configuration as notes at the start
  of every game. These can be viewed from the in-progress game dump and the
  final game morgue.
