#!/bin/bash

# A bash script to setup qw.rc from the qw git repo.


rc_file="qw.rc"
lua_files="qw.lua"
version=$(git describe)
out_file="$rc_file".out
lua_marker='\# include = qw.lua'

read -d '' usage_string <<EOF
$(basename $0) [-m MARKER] [-o OUT-FILE] [RC-FILE] [LUA-FILE...]
Replace an instance of the MARKER string in RC-FILE with the contents of the
LUA-FILE arguments.
Default marker string: $marker
Default input rc file: $rc_file
Default input lua file(s): $lua_files
Default output file: $out_file
EOF

while getopts "h?m:o:" opt; do
    case "$opt" in
        h|\?)
            echo -e "$usage_string"
            exit 0
            ;;
        o)  out_file="$OPTARG"
            ;;
        m)  lua_marker="$OPTARG"
            ;;
    esac
done
shift $(($OPTIND - 1))

if [ ! -z "$1" ]; then
    rc_file="$1"
    shift
fi

if [ $# -ne 0 ]; then
    lua_files=$@
fi

set -e

rc_text=$(cat $rc_file)
lua_text=$(cat $lua_files)
lua_text="${lua_text/\%VERSION\%/$version}"
printf "%s\n" "${rc_text/$lua_marker/$lua_text}" > "$out_file"

rc_nlines=$(echo "$rc_text" | wc -l)
lua_nlines=$(echo "$lua_text" | wc -l)
echo "Added $rc_nlines lines from $rc_file to $out_file"
echo "Added $lua_nlines lines from $lua_files to $out_file"
