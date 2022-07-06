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
* You may want to edit some of the configuration lines near the top of `qw.rc`.
  For example, edit the various COMBO variables to choose which combos qw will
  play. See the comments in the *Gameplay* section for details.
* Run crawl locally with command like `./crawl -rc qw/qw.rc -rcdir qw`, where
  here the repo is in a directory named `qw`. The `-rcdir` option is necessary
  for `crawl` to find the `qw.lua` file. Alternately you can put the contents
  of `qw.lua` directly in `qw.rc` per the instructions below for online play.
* Enter a name if necessary and start game. If you didn't change the
  `AUTO_START` variable, press "Tab".
* Enjoy!

The file qw.exp is a simple expect script that automates running qw for many
games in a row. The `AUTO_START` variable should be left at false when when
using this. (With minor modifications, this can also be used to run games on a
remote server over ssh.)

## Running on a WebTiles server
Please don't run qw on an official server unless you have permission from the
server admin. Misconfigured (or even well-configured) bots can eat up server
CPU from actual players.  If you do have permission from your server admin,
server please add the name of the account that you are using for qw to the
Sequell "bot" nick with `!nick bot <accountname>` so that games on the account
can be easily filtered out of queries. Also, please don't run qw on the same
account that you use for your own personal games.

Steps:
* In a text editor, open the `qw.rc` file from this repo.
* In the *Interface* section, on the lines with `: DELAYED = false` and `:
  AUTO_START = false`, change `false` to `true`
* At the end of the contents of `qw.rc`, put the contents of the `qw.lua` file
  from this repository. Note that first line of `qw.lua` with `{` and the last
  line with `}` must also be included, otherwise the Lua code won't execute.
* Copy the full contents of your modified `qw.rc` file. It's wise to also save
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

## Miscellaneous tips for coding/testing qw
* Run qw locally with the DCSS command-line option -seed <n> to use a seeded
  RNG for (mostly) reproducible testing
* See the Debugging section of qw.rc for variables to enable for debugging
  purposes.
* Put code you want to test in the "ttt()" funtion on the bottom; make it run
  by macroing some key to "===ttt"
* Use the included `make-qw-rc.sh` script to assemble a full qw rcfile from a
  base rcfile you've made from qw.rc and your modified qw.lua. This script also
  sets a custom version string based on the latest git annotated tag and commit.
* qw outputs its configuration as well as its current version as notes at the
  start of every game. These can be viewed from the in-progress game dump and
  the final game morgue.
