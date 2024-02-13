#!/bin/bash

# A bash script to run qw locally

name=qw
num_games=1
rc_dir=$(pwd)
rc_file=qw.rc
track_count=

read -d '' usage_string <<EOF
usage: $(basename $0)  [-n <num>] [-d <dir>] [-r <file>] [-u <name>] [-t] <dir>
Run qw from the crawl directory <dir>.

    -n <num>        number of games to play. Default: $num_games
    -d <dir>        RC directory for includes. Default: $rc_dir
    -r <file>       RC file. Default: $rc_file
    -u <name>       player name. Default: $name
    -t              track and resume the number of completed games from a .count file.
EOF

while getopts "h?n:u:d:r:t" opt; do
    case "$opt" in
        h|\?)
            echo -e "$usage_string"
            exit 0
            ;;
        n)  num_games="$OPTARG"
            ;;
        u)  name="$OPTARG"
            ;;
        d)  rc_dir="$OPTARG"
            ;;
        r)  rc_file="$OPTARG"
            ;;
        t)  track_count=1
            ;;
    esac
done
shift $(($OPTIND - 1))

crawl_dir="$1"
if [ -z "$crawl_dir" ] ; then
    echo -e "$usage_string"
    exit 1
fi

set -e

if [ ! -e "$crawl_dir/morgue" ] ; then
    mkdir "$crawl_dir/morgue"
fi

if [ ! -e "$crawl_dir/morgue/$name" ] ; then
    mkdir "$crawl_dir/morgue/$name"
fi

cd "$crawl_dir"

count=1
if [ $track_count ] && [ -e "$name".count ] ; then
    count=$(cat "$name".count)
    echo "Continuing from iteration $count"
fi

while [ $count -le $num_games ]
do
    if [ $track_count ] ; then
        echo $count > "$name".count
    fi

    echo "Running iteration $count"

    ./crawl -lua-max-memory 96 -no-throttle -wizard -name "$name" \
        -morgue "$crawl_dir/morgue/$name" -rcdir "$rc_dir" -rc "$rc_file"

    # We ended without finishing our current game, so back up save and
    # c_persist files, then exit.
    if [ -e ".$name.cs" ] ; then
        echo "Game suspended."
        echo "Backing up save to $name.cs.bak and persist to $name.rc.persist.bak"
        cp ".$name.cs" "$name.cs.bak"
        cp "$rc_file".persist "$rc_file".persist.bak
        exit 1
    fi

    count=$(( $count + 1 ))
done

if [ $track_count ] ; then
    rm "$name".count
fi

echo "Finished $num_games iterations"

exit 0
