#!/bin/bash

# A bash script to batch runs of qw

do_clean=
base_name=qw
num_instances=1
num_games=1
rc_dir=$(pwd)

read -d '' usage_string <<EOF
$(basename $0) [-i <num>] [-n <num>] [-b <name>] [-d <dir>] [-c] <dir>
Run qw in parallel instances from tmux using the crawl directory <dir>.

    -i <num>        Number of instances to run. Default: $num_instances
    -n <num>        Number of games to run for each instance. Default: $num_games
    -b <name>       Base player name. Default: $base_name
    -d <dir>        RC directory for any includes. Default: $rc_dir
    -c              Remove any existing logfile, milestones, save, and count files.
EOF

while getopts "h?ci:n:b:d:" opt; do
    case "$opt" in
        h|\?)
            echo -e "$usage_string"
            exit 0
            ;;
        c)  do_clean=1
            ;;
        i)  num_instances="$OPTARG"
            ;;
        n)  num_games="$OPTARG"
            ;;
        b)  base_name="$OPTARG"
            ;;
        d)  rc_dir="$OPTARG"
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

if [ $do_clean ] ; then
    rm -f "$crawl_dir/logfile" "$crawl_dir/milestones" \
        "$crawl_dir"/."$base_name"*.cs "$crawl_dir"/*.count
fi

tmux new-session -d -s "$base_name"

username=
count=0
while [ $count -lt $num_instances ]
do
    username="${base_name}$count"

    if [ $count -eq 0 ] ; then
        tmux rename-window "$username"
    else
        tmux new-window -a -t "$base_name" -n "$username"
    fi

    tmux send-keys "util/run-qw.sh -t -n $num_games -u \"$username\" \
        -d \"$rc_dir\" -r \"$rc_dir/$username\".rc \"$crawl_dir\"" C-m

    count=$(( $count + 1 ))
done

tmux attach-session -t "$base_name"
exit 0
