#!/bin/bash

# A bash script to combine qu lua from the qw git repo.

rc_file=
first_lua_file="variables.lua"
lua_dir="source"
version=$(git describe)
lua_out_file="qw.lua"
rc_out_file="qw-final.rc"
out_file=
rc_marker='\# include = qw.lua'

read -d '' usage_string <<EOF
$(basename $0)  [-d LUA-DIR] [-r RC-FILE [-m MARKER]] [-o OUT-FILE]
Combine lua files from a directory into a single lua file, optionally combining
this with a crawl rc file based on a marker string.
Default lua directory: $lua_dir
Default output lua file: $lua_out_file
Default rc output file (with -r): $rc_out_file
Default rc file lua marker string (with -r): $rc_marker
EOF

while getopts "h?m:o:r:" opt; do
    case "$opt" in
        h|\?)
            echo -e "$usage_string"
            exit 0
            ;;
        o)  out_file="$OPTARG"
            ;;
        m)  rc_marker="$OPTARG"
            ;;
        r)  rc_file="$OPTARG"
            ;;
    esac
done
shift $(($OPTIND - 1))

set -e

lua_text=$(cat $lua_dir/$first_lua_file)
lua_text+=$'\n'
lua_text+=$(find source -iname '*.lua' -not -name "$first_lua_file" | sort | xargs cat)
lua_text="${lua_text/\%VERSION\%/$version}"

if [ -n "$rc_file" ]; then
    if [ -z "$out_file" ]; then
        out_file="$rc_out_file"
    fi

    rc_text=$(cat $rc_file)
    lua_text=$(printf "<\n%s\n>" "$lua_text")
    printf "%s\n" "${rc_text/$rc_marker/$lua_text}" > "$out_file"
    rc_nlines=$(echo "$rc_text" | wc -l)
    echo "Added $rc_nlines lines from $rc_file to $out_file"
else
    if [ -z "$out_file" ]; then
        out_file="$lua_out_file"
    fi

    printf "<\n%s\n>\n" "$lua_text" > "$out_file"
fi

lua_nlines=$(echo "$lua_text" | wc -l)
echo "Added $lua_nlines lines from $lua_dir to $out_file"
