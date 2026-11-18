#!/bin/bash

# A bash script to combine qu lua from the qw git repo.

rc_file=
first_lua_file="header.lua"
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

# The version substitution is done with awk because bash 3.2, the macOS
# default, takes minutes to run a pattern substitution on a string this large.
lua_text=$( { cat "${lua_dir}/${first_lua_file}";
    find source -iname '*.lua' -not -name "$first_lua_file" | sort | xargs cat; } \
    | awk -v version="$version" \
        '!done && sub(/%VERSION%/, version) { done = 1 } { print }')

if [ -n "$rc_file" ]; then
    if [ -z "$out_file" ]; then
        out_file="$rc_out_file"
    fi

    lua_text=$(printf "<\n%s\n>" "$lua_text")
    lua_tmp=$(mktemp)
    trap 'rm -f "$lua_tmp"' EXIT
    printf "%s" "$lua_text" > "$lua_tmp"
    # The marker is matched literally, so drop the backslash that the default
    # needed when this was a bash pattern.
    awk -v marker="${rc_marker#\\}" -v lua_file="$lua_tmp" '
        BEGIN {
            while ((getline line < lua_file) > 0)
                lua = lua (n++ ? "\n" : "") line
        }
        !done && (i = index($0, marker)) {
            $0 = substr($0, 1, i - 1) lua substr($0, i + length(marker))
            done = 1
        }
        { print }' "$rc_file" > "$out_file"
    rc_nlines=$(wc -l < "$rc_file")
    echo Added $rc_nlines lines from $rc_file to $out_file
else
    if [ -z "$out_file" ]; then
        out_file="$lua_out_file"
    fi

    printf "<\n%s\n>\n" "$lua_text" > "$out_file"
fi

lua_nlines=$(echo "$lua_text" | wc -l)
echo Added $lua_nlines lines from $lua_dir to $out_file
