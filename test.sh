#!/bin/bash
# Scarp pad for testing script snippets
export GLOBALVAR="GLOBAL"
createNode () {
    local ZONE=$1
    echo "zone-$ZONE start + $GLOBALVAR"
}
ZONELIST='1 2 3'
for ZONE in $ZONELIST; do createNode "$ZONE" & done
wait

