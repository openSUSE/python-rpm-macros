#!/bin/bash

REALPATH=$(realpath "${BASH_SOURCE[0]}")
MYPATH=$(dirname "$REALPATH")

(
    cd "$MYPATH"
    perl embed-macros.pl > macros
)

rpmspec -v \
    --macros=$MYPATH/macros:/usr/lib/rpm/macros:/etc/rpm/macros.python:/etc/rpm/macros.python3 \
    -P "$1"
