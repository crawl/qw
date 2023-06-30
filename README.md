# qw

This is the [DCSS](https://github.com/crawl/crawl) bot qw, the first bot to win
DCSS with no human assistance. Originally written by
[elliptic](https://github.com/elliptic/), it's now developed and maintained by
the DCSS devteam. A substantial amount of code here was contributed by elliott
or borrowed from N78291's bot "xw", and many others have contributed fixes and
suggestions.

qw can play most species and background combinations using either melee or
ranged weapons, and has some basic grasp of how many gods work. Note though
that most spells and abilities aren't used, and qw does not have a high
winrate. It has won games with 3 and 15 runes, and we maintain qw so it can
continue to play and win the current version. See
[docs/accomplishments.md](docs/accomplishments.md) for current and past
achievements.

Please post bug reports as issues on the official crawl qw repository:

https://github.com/crawl/qw/issues/new

If you're interested in contributing to qw development, see the [debugging
doc](docs/debugging.md) for help with debugging.

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
  ./crawl -lua-max-memory 32 -rc /path/to/qw/qw.rc -rcdir /path/to/qw
  ```
  The `-rcdir` option is necessary for crawl to find qw.lua.

This method makes rcfile modifications easier and debugging easier due to line
numbers from error messages.

Note that when running qw on a server, you can still use this method if you use
the `qw.lua` file as the rcfile contents of another account. You would then
modify your `include = qw.lua` statement to be `include = ACCOUNT.rc` where
`ACCOUNT` is the account name.

#### Method 2: lua directly in the rcfile

This puts all lua directly into the rcfile. This is an easy way to run qw from
a single account.

Steps:
* Run `make-qw.sh -r qw.rc` to inline all lua directly into the contents of
  `qw.rc`, saving the results in `qw-final.rc`.
* To run qw locally use a command like:
  ```bash
  ./crawl -lua-max-memory 32 -rc /path/to/qw/qw-final.rc
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

### Running on a WebTiles or dgamelaunch server

qw requires more memory and cpu than what's allowed for official online
servers, so you will need to run your own server. Please don't try to run qw on
an official server. Misconfigured (or even well-configured) bots can eat up
server server resources.

Your server needs to start crawl with the arguments `-lua-max-memory 32` and
`-no-throttle`. For WebTiles, you can add these under the `options` section of
the game entry. To track games for your instance of qw, you can set up
[Sequell](https://github.com/crawl/sequell) or the DCSS
[scoring](https://github.com/crawl/scoring) scripts.

## qw Configuration

Most qw variables are straightforward and are described in in comments in
qw.rc. Some important and more complicated variables are described here. Note
that lines in qw.rc beginning with `:` define Lua variables and must be valid
Lua code, otherwise the lines are Crawl options as described in the [options
guide](https://github.com/crawl/crawl/blob/master/crawl-ref/docs/options_guide.txt).

### Starting and Action Delay

Set the `AUTO_START` variable to `true` to have qw start automatically when a
game begins. Otherwise, press "Tab" to start and stop execution.

If you're spectating qw, you may want to set `DELAYED` to `true` to add a short
delay between each action. The delay time is stored in `DELAY_TIME` with a
default of 125 ms, which gives a good spectator experience.

Since clua works on the server side, WebTiles drawing can lag behind things
actually happening. To see more current events just refresh the page and press
"Tab". Alternatively, run or watch the bot in console (via ssh).

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
told to convert explicitly by the [goal list](#goals).

Gods who have at least partly implemented are *BCHLMOQRTUXY1*. Currently qw has
the most success with *Okawaru*, *Trog*, and *Ru*, roughly in that order. For
combos, GrFi, GrBe, MiFi, MiBe, GrHu, and MiHu are most successful.

#### Combo cycles

To have qw cycle through a set of combos, set `COMBO_CYCLE` to `true` and edit
`COMBO_CYCLE_LIST`. This list uses the same syntax as the `combo` option, but
with an optional `^<god initials>` suffix. The set of letters in `<god
initials>` gives the set of gods qw is allowed to worship for that combo.
Additionally, after this god list, you can specify a goal name from
`GOALS` with a `!<plan>` suffix. For example, the default list:

```lua
COMBO_CYCLE_LIST = "GrFi.waraxe^OR, MiBe.handaxe, GrHu^O"
```

has qw cycle through GrFi of either Okawaru or Ru, and GrHu of Okawaru.

### Goals

The `GOALS` variable defines a table of strings defining sets of goals
for qw to complete in sequence. Each key in this table is a descriptive string
that can be used in the `DEFAULT_GOAL` variable or in the
`COMBO_CYCLE_LIST` variable above to have qw execute that set of goals. The
entries in `GOALS` are case-insensitive, comma-separated strings of
*goals* that qw will follow in sequence.

The default goal is `Normal`, which is a meta goal that has qw proceed
through a 3-rune route that gives qw good success. This is mostly equivalent
to the following goal list:

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

If `Normal` is followed by additional entries in the goal list, qw will
proceed to those after its `Shopping` goal is complete. Hence a viable 15
Rune route could be expressed as:

```
"Normal, God:TSO, Crypt, Tomb, Pan, Slime:5, Hells, Abyss, Zot"
```

This will have qw abandon its current god for the Shining One after shopping is
complete before heading through Crypt, Tomb, and the other extended branches.

The other types of goal entries are:

* `<branch>`

  Where `<branch>` is the branch name reported by `you.where()`. qw will fully
  explore all levels in sequence in that branch as well as get any branch
  runes before proceeding to the next goal.

  Examples: `D`, `Lair`, `Vaults`

* `<branch>:<range>`

  The <range> can be a single level or a range of levels separated with a dash.
  The levels in this range are fully explored in sequence, although qw will
  potentially explore just outside of the level range to find all stairs for
  levels in the range. If the range includes a level with a rune, qw will find
  this rune before considering the goal complete.

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

* `Win`, `Orb`, and `Escape`

  The `Orb` goal has qw seek the Orb of Zot on Zot:5 and pick it up. The
  `Escape` goal has it go to D:1 and exit the dungeon, which ends the game. The
  `Win` goal does the `Orb` goal followed by the `Escape` goal. qw always
  switches to the `Win` goal when it completes all entries in its goal list. Note
  that the `Orb` goal has qw dive through all levels of Zot to look for the orb
  on Zot:5. Proceed this goal with e.g. `Zot:1-4` or `Zot` if you want to explore
  more of the Zot
branch.

* `Zig`, or `Zig:<num>`

  Enter a ziggurat, clear it through level `<num>`, and exit. If `<num>` is not
  specified, qw clears the entire ziggurat.

* `Hells`

  Do Hell and the 4 Hell branches in random order.

* `Quit`

  Quit the game immediately. This is useful as a final goal when testing qw.

#### Some notes about exploration

qw considers a level explored if it's been autoexplored to completion at least
once, all its required stone upstairs and downstairs are reachable, and any
rune on the level has been obtained. Other types of unreachable areas,
transporters, and runed doors don't prevent qw from considering a level
autoexplored. In portals, the Abyss, and Pan, qw always opens all runed doors
and explores all transporters. If qw must travel through unexplored levels that
aren't part of its current goal, it will explore only as much as necessary
to find the necessary stairs and then take them. This behaviour includes
situations like being shafted.

For Hell branches, goals like `Rune:Geh`, `Rune:Tar`, etc. are good
choices, since they have qw dive to and get the rune while exploring as little
as possible of the final level. For a branch like Slime, a goal of
`Slime:5` is better, since it makes qw dive through Slime but explore Slime:5
fully to obtain the loot after the Royal Jelly is dead.
