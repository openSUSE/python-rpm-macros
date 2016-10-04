#!/bin/bash

SRC=${BASH_SOURCE[0]}
REALPATH=$(readlink -f "$SRC")
MYPATH=$(dirname "$REALPATH")

(
    cd "$MYPATH"
    perl embed-macros.pl > macros
)

rpmspec -v \
    --macros=$MYPATH/macros:/usr/lib/rpm/macros:/etc/rpm/macros.python:/etc/rpm/macros.python3 \
    -P "$1"
