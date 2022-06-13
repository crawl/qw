# qw

This rcfile is elliptic's DCSS bot "qw", the first bot to win DCSS with no
human assistance. A substantial amount of code here was contributed by elliott
or borrowed from N78291's bot "xw", and many others have contributed as well.
The bot is now maintained by the DCSS devteam. Please post bug reports as
issues on the official crawl qw repository:

https://github.com/crawl/qw/issues/new

The current version of qw can play most species and background combinations in
a melee-focused way and has some basic grasp of how many gods work (see qw.rc
for configuration details). Note though that most spells and racial abilities
aren't used, and qw is not very good! It can win games with 3 runes for combos
like GrBe, and we try to maintain qw so it can continue to play and win the
current version. See `??qw` in the LearnDB for a list of its current and past
achievements as well as its limitations.

## Running on remote DCSS server
* Please make sure you have permission to run a bot on your server of choice!
  Misconfigured (or even well-configured) bots can eat up server CPU from
  actual players.
* In a text editor, open the `qw.rc` file from this repo.
* On the lines with `: DELAYED = false` and `: AUTO_START = false`, change
  `false` to `true`
* You may also want to edit some of the configuration lines near the top
  of qw.rc. For example, edit the various COMBO variables to choose which
  combos qw will play. See the comments in this section for details.
* At the end of the contents of `qw.rc`, put the contents of the `qw.lua` file
  from this repository. Note that first line of `qw.lua` with `{` and the last
  line with `}` must also be included, otherwise the Lua code won't execute.
* Copy the final contents of your modified `qw.rc` file. It's wise to also save
  this to a new file for ease of future modifications.
* Go to your WebTiles server lobby.
* Click the "(edit rc)" link for DCSS trunk, paste the contents of the modified
  `qw.rc` you made, and click Save.
* Run DCSS trunk, either in WebTiles or in console. If you didn't change the
  `AUTO_START` variable to `true`, press "Tab".
* Enjoy!

Since clua works on the server side, WebTiles drawing can lag behind things
actually happening, so the IRC bot [Sequell](https://github.com/crawl/sequell)
may tell you your character killed Sigmund or died to him before you see that
with your own eyes. To see more current events just refresh the page and press
"Tab". Alternatively, run or watch the bot in console (via ssh).

If you are familiar with Sequell, please add the name of the account that
you are using for qw to the "bot" nick with `!nick bot <accountname>` so
that games on the account can be easily filtered out of queries. Also, please
don't run qw on the same account that you use for your own personal games!

## Running locally
* Clone this repo.
* Run crawl locally with command like `./crawl -rc qw/qw.rc -rcdir qw`, where
  here the repo is in a directory named `qw`. The `-rcdir` option is necessary
  for `crawl` to find the `qw.lua` file. Alternately you can put the contents of
  `qw.lua` directly in `qw.rc` per the instructions above for online play.
* Enter name if necessary and start game. If you didn't change the
  `AUTO_START` variable, press "Tab".
* Enjoy!

The file qw.exp is a simple expect script that automates running qw for many
games in a row. The `AUTO_START` variable should be left at false when when
using this. (With minor modifications, this can also be used to run games on a
remote server over ssh.)

## Miscellaneous tips for coding/testing qw
* Run qw locally with the DCSS command-line option -seed <n> to use a seeded
  RNG for (mostly) reproducible testing
* Uncomment the "say(plandata[2])" line in the cascade function to track what
  the bot is doing (very spammy)
* Put code you want to test in the "ttt()" funtion on the bottom; make it run
  by macroing some key to "===ttt"
