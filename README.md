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

## Running locally
It's best to run qw either locally or on your own server. You can set up
[Sequell](https://github.com/crawl/sequell) or the DCSS
[scoring](https://github.com/crawl/scoring) scripts to track its statistics.

Steps:
* Clone this repo.
* You may want to edit some of the configuration in [qw.rc](qw.rc). See the
  comments  in that file and the [configuration](#configuration) section below
  for more details.
* Run crawl locally with command like `./crawl -rc qw/qw.rc -rcdir qw`, where
  here the repo is in a directory named `qw`. The `-rcdir` option is necessary
  for `crawl` to find the [qw.lua](qw.lua) file. Alternately you can put the
  contents of qw.lua directly in qw.rc per the instructions below for online
  play.
* Enter a name if necessary and start game. If you didn't change the
  `AUTO_START` variable, press "Tab".
* Enjoy!

The file [qw.exp](qw.exp) is a simple expect script that automates running qw
for many games in a row. The `AUTO_START` variable should be left at false when
when using this. (With minor modifications, this can also be used to run games
on a remote server over ssh.)

## Running on a WebTiles server
Please don't run qw on an official server unless you have permission from the
server admin. Misconfigured (or even well-configured) bots can eat up server
CPU from actual players. If you do have permission from your server admin,
server please add the name of the account that you are using for qw to the
Sequell "bot" nick with `!nick bot <accountname>` so that games on the account
can be easily filtered out of queries. Also, please don't run qw on the same
account that you use for your own personal games.

Steps:
* In a text editor, open the [qw.rc](qw.rc) file from this repo.
* In the *Interface* section, on the lines with `: DELAYED = false` and `:
  AUTO_START = false`, change `false` to `true`
* At the end of the contents of qw.rc, put the contents of the [qw.lua](qw.lua)
  file from this repository. Note that first line of `qw.lua` with `{` and the
  last line with `}` must also be included, otherwise the Lua code won't execute.
* Copy the full contents of your modified qw.rc file. It's wise to also save
  this to a new file for ease of future modifications.
* Go to your WebTiles server lobby.
* Click the "(edit rc)" link for DCSS trunk, paste the contents of the modified
  `qw.rc` you made, and click Save.
* Run DCSS trunk, either in WebTiles or in console. If you didn't change the
  `AUTO_START` variable to `true`, press "Tab".
* Enjoy!

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

The simplest way to change the combo qw plays is with the `combo` rcfile
option. Change this to your desired combos, then change `GOD_LIST` to the set
of gods for qw is allowed to worship. It will worship the first of these it
finds. Each entry in `GOD_LIST must be the full god name. Gods who have been at
least partially implemented: `BCHLMOQRTUXY1`. Gods who are actually pretty
decent on qw: `CMORT`.

To have qw cycle through a set of combos, set `COMBO_CYCLE` to `true` and edit
`COMBO_CYCLE_LIST`. This list uses the same syntax as the `combo` option, but
with an optional `^<god initials>` suffix. The set of letters in `<god
initials>` gives the set of gods qw is allowed to worship for that combo.
Additionally, after this god list, you can specify a game plan name from
`GAME_PLANS` with a `!<plan>` suffix. For example, the default list:
```lua
COMBO_CYCLE_LIST = "GrBe.handaxe, MiFi.waraxe^OM, GrFi.waraxe^O!15runes"
```
has qw cycle through GrBe, MiFi of either Okawaru or Makhleb, and GrFi of
Okawaru attempting the 15 runes plan.

### Game plans
The `GAME_PLANS` variable defines a table of possible plans for qw to follow in
a game. Each key is a descriptive string that can be used in the PLAN variable
or in the `COMBO_CYCLE_LIST` variable above. Each entry is a string of
comma-separated plans that qw will follow in the given order. A plan can be any
of:

* A level range, which can be a branch name like `D`, `Lair`, `Depths`, etc.,
  or a range like `D:1-11`, `Vaults:1-4`. qw will fully explore this level
  range, also trying to get all relevant runes. For the randomized Lair
  branches, specify all four of them in your preferred order, and qw will skip
  any that don't generate. Don't specify Temple, which qw visits automatically
  as necessary or any portal other than `Zig`.

  If the final plan entry includes Zot:5 in its range (e.g. `Zot`), qw picks up
  the Orb as soon as possible and tries to go win without fully exploring
  Zot:5. Otherwise it will fully explore Zot:5 but not pick up the Orb until it
  reaches the `Orb` plan.

* `Normal`, which proceeds through qw's default (3-rune) route. This is:

  D:1-11 -> Lair -> D:12-D:15 -> Orc -> random Lair branch -> Vaults:1-4 ->
  other Lair Branch -> Depths -> Vaults:5 -> Shopping -> Zot -> Win

  If `Normal` is followed by another plan, qw will proceed to that plan after
  its Shopping plan is complete. Note that this route is subject to the
  `LATE_ORC` and `EARLY_SECOND_RUNE` variables.

* `Shopping`, which has qw try to buy the items it hasput on its shopping list.

* `TSO`, which has qw convert to the Shining One.

* `Orb`, which should only be used if you want qw to explore some or all of Zot
  and then do something other than win.

These plan names are not case-sensitive.

## Debugging
Set `DEBUG_CHANNELS` to `true` to enable debug output. Then put the message
channels you want to see in the list `DEBUG_CHANNELS`. The available channels
are "main", the default for debug messages, "plans", which shows all plan
execution and results (very spammy), and "skills", which shows information
about skill selection.

Also see the options `SINGLE_STEP` to have qw take one action at a time with
the Tab key, and `WIZMODE_DEATH` to control whether it chooses to die in Wizard
mode.

### Miscellaneous tips for coding and testing
* Run qw locally with the DCSS command-line option -seed <n> to use a seeded
  RNG for (mostly) reproducible testing
* Put code you want to test in the `ttt()` funtion on the bottom; make it run
  by macroing some key to `===ttt`
* Use the included `make-qw-rc.sh` script to assemble a full qw rcfile from a
  base rcfile you've made from qw.rc and your modified qw.lua. This script also
  sets a custom version string based on the latest git annotated tag and commit.
* qw outputs its configuration as well as its current version as notes at the
  start of every game. These can be viewed from the in-progress game dump and
  the final game morgue.
