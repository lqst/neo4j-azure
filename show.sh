#!/bin/bash
if [ -z $1 ] ; then
  echo "Usage: call me with resource group name to show nodes in the cluster"
  exit 1
fi
RESOURCE_GROUP=$1

echo "Show cluster nodes in $RESOURCE_GROUP"

listNode () {
    local ZONE=$1
    echo core-$ZONE PublicIp: $(az vm show -d -g $RESOURCE_GROUP -n core-$ZONE --query publicIps -o tsv) \
    client-nic: $(az network nic show -g $RESOURCE_GROUP -n client-nic-core$ZONE  --query ipConfigurations[].privateIpAddress -o tsv)  \
    cluster-nic: $(az network nic show -g $RESOURCE_GROUP -n cluster-nic-core$ZONE  --query ipConfigurations[].privateIpAddress -o tsv)
}

ZONELIST='1 2 3'
for ZONE in $ZONELIST; do listNode "$ZONE" & done
wait