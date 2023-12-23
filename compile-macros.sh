#!/bin/bash

# The set of flavors for which we produce macros. Not identical to
# the buildset predefined for specific distributions (see below)
FLAVORS="python2 python3 python310 python311 python312 pypy3"

### flavor-specific: generate from flavor.in
for flavor in $FLAVORS; do
    sed 's/#FLAVOR#/'$flavor'/g' flavor.in > macros/020-flavor-$flavor
    if [ "$flavor" = "python2" ]; then
        # special old-style package provides and obsoletes for python2
        echo "%${flavor}_provides python" >> macros/020-flavor-$flavor
    fi
done


### buildset: %pythons, %python_module and %add_python, coming from
# the current build target's prjconf
echo "Setting buildset:"
echo "## Python Buildset Begin" | tee macros/040-builset-start
# First try to find the block from Factory
sed -n '/## PYTHON MACROS BEGIN/,/## PYTHON MACROS END/ p' ~/.rpmmacros | tee macros/041-buildset
# If that fails, find the old definitions (SUSE:SLE-15-SP?:GA, openSUSE:Leap:15.?)
if [ ! -s macros/041-buildset ]; then
    sed -n '/%pythons/,/%add_python/ p' ~/.rpmmacros | tee macros/041-buildset
fi
# If we still have nothing (different distro, custom prjconf, building
# python-rpm-macros outside of obs), use the default file
if [ ! -s macros/041-buildset ]; then
    tee macros/041-buildset < default-prjconf
fi
echo "## Python Buildset End" | tee macros/042-builset-end

### Lua: generate automagic from macros.in and macros.lua
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
) > macros/050-automagic


### final step: cat macros/*, but with files separated by additional newlines
sed -e '$s/$/\n/' -s macros/* > macros.python_all
