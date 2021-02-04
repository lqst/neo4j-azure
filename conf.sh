#!/bin/bash
if [ -z $1 ] ; then
  echo "Usage: call me with resource group name"
  exit 1
fi
RESOURCE_GROUP=$1

echo "configure and restart of cluster in $RESOURCE_GROUP"

configureAndRestart () {
    local ZONE=$1
    export ZONE=$ZONE
    echo "zone-$ZONE configure and restart"

    # Prepare neo4j.conf
    envsubst < conf.template > neo4j.conf.core-$ZONE

    # Get public ip of the vm
    export default_advertised_address=$(az vm show -d -g $RESOURCE_GROUP -n core-$ZONE --query publicIps -o tsv)
    echo "core-$ZONE: default_advertised_address: ${default_advertised_address}"
    
    # "Copy" neo4j.conf to vm
    # Encode it
    base64 -i neo4j.conf.core-$ZONE -o neo4j.conf.core-$ZONE.base64
    export NEO4J_ENCODED_CONF=$(cat neo4j.conf.core-$ZONE.base64)

    # Decode it
    echo "core-$ZONE: Add neo4j.conf"
    az vm run-command invoke -g $RESOURCE_GROUP -n core-$ZONE  --command-id RunShellScript \
      --scripts "sudo echo ${NEO4J_ENCODED_CONF} | base64 -d > /etc/neo4j/neo4j.conf"

    # Restart 
    az vm run-command invoke -g $RESOURCE_GROUP -n core-$ZONE  --command-id RunShellScript \
      --scripts "sudo systemctl restart neo4j"
}

export initial_discovery_members=core-1:5000,core-2:5000,core-3:5000

ZONELIST='1 2 3'
for ZONE in $ZONELIST; do configureAndRestart "$ZONE" & done
wait