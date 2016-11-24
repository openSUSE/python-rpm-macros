#!/bin/bash

FLAVORS="python2 python3 pypy3"

for flavor in $FLAVORS; do
    sed 's/#FLAVOR#/'$flavor'/g' flavor.in > macros/020-flavor-$flavor
done

perl embed-macros.pl macros.in macros.lua > macros/040-automagic

# cat macros/*, but with files separated by additional newlines
sed -e '$s/$/\n/' -s macros/* > macros.python_all
