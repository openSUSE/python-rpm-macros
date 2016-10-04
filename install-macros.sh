#!/bin/bash

REALPATH=$(realpath "${BASH_SOURCE[0]}")
MYPATH=$(dirname "$REALPATH")

PROJECT="$1"
[ -z "$PROJECT" ] && PROJECT="home:matejcik:messing-with-macros"

(
    cd "$MYPATH"
    echo "Macros:"
    perl embed-macros.pl
    echo ":Macros"
) | osc meta prjconf $PROJECT -F -
