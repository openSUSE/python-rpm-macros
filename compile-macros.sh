#!/bin/bash

FLAVORS="python2 python3 pypy3"

# generate flavors from flavor.in
for flavor in $FLAVORS; do
    sed 's/#FLAVOR#/'$flavor'/g' flavor.in > macros/020-flavor-$flavor
done

# generate automagic from macros.in and macros.lua
(
    # copy macros.in up to LUA-MACROS
    sed -n -e '1,/^### LUA-MACROS ###$/p' macros.in

    # include "functions.lua", without empty lines, as %_python_definitions
    echo "%_python_definitions %{lua:"
    sed -n -r \
        -e 's/\\/\\\\/g' \
        -e '/^.+$/p' \
        functions.lua
    echo "}"

    INFUNC=0
    # brute line-by-line read of macros.lua
    IFS=""
    while read -r line; do
        if echo "$line" | grep -q '^function '; then
            # entering top-level Lua function
            INFUNC=1;
            echo "$line" | sed -r -e 's/^function (.*)\((.*)\)$/%\1(\2) %{lua: \\/'
        elif [ "$line" == "end" ]; then
            # leaving top-level Lua function
            INFUNC=0;
            echo '}'
        elif [ $INFUNC == 1 ]; then
            # inside function
            # double backslashes and add backslash to end of line
            echo "$line" | sed -e 's/\\/\\\\/g' -e 's/$/\\/'
        else
            # outside function, copy
            # (usually this is newline)
            echo "$line"
        fi
    done < macros.lua

    # copy rest of macros.in
    sed -n -e '/^### LUA-MACROS ###$/,$p' macros.in
) > macros/040-automagic

# perl embed-macros.pl macros.in macros.lua > macros/040-automagic.orig

# cat macros/*, but with files separated by additional newlines
sed -e '$s/$/\n/' -s macros/* > macros.python_all
