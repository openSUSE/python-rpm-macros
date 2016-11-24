#!/bin/bash

REALPATH=$(realpath "${BASH_SOURCE[0]}")
MYPATH=$(dirname "$REALPATH")

(
    cd "$MYPATH"
    ./compile-macros.sh
)

rpmspec -v \
    --macros=$MYPATH/macros.python_all:/usr/lib/rpm/macros:/etc/rpm/macros.python:/etc/rpm/macros.python3 \
    -P "$1"
