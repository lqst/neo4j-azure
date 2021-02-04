#!/bin/bash
if [ -z $1 ] ; then
  echo "Usage: call me with resource group name to show nodes in the cluster"
  exit 1
fi
RESOURCE_GROUP=$1

echo "Show cluster nodes in $RESOURCE_GROUP"

configureAndRestart () {
    local ZONE=$1
    echo core-$ZONE: $(az vm show -d -g $RESOURCE_GROUP -n core-$ZONE --query publicIps -o tsv)
    
}

ZONELIST='1 2 3'
for ZONE in $ZONELIST; do configureAndRestart "$ZONE" & done
wait