#!/bin/bash

PROJECT="$1"
[ -z "$PROJECT" ] && PROJECT="home:matejcik:messing-with-macros"

(
    echo "Macros:"
    perl embed-macros.pl
    echo ":Macros"
) | osc meta prjconf $PROJECT -F -
