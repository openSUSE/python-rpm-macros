#!/bin/bash

REALPATH=$(realpath "${BASH_SOURCE[0]}")
MYPATH=$(dirname "$REALPATH")

(
    cd "$MYPATH"
    ./compile-macros.sh
)

rpmspec -v \
    --macros=/usr/lib/rpm/macros:/etc/rpm/macros.python2:/etc/rpm/macros.python3:$MYPATH/macros.python_all \
    -P "$1"
