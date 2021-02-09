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

    # Get internal ip address for cluster nic
    export cluster_nic_ip=$(az network nic show -g $RESOURCE_GROUP -n cluster-nic-core$ZONE  --query ipConfigurations[].privateIpAddress -o tsv)
    echo "core-$ZONE: cluster_nic_ip: ${cluster_nic_ip}"

    # Get internal ip address for client nic
    export client_nic_ip=$(az network nic show -g $RESOURCE_GROUP -n client-nic-core$ZONE  --query ipConfigurations[].privateIpAddress -o tsv)
    echo "core-$ZONE: client_nic_ip: ${client_nic_ip}"

    # Get public ip of the vm
    export default_advertised_address=$(az vm show -d -g $RESOURCE_GROUP -n core-$ZONE --query publicIps -o tsv)
    echo "core-$ZONE: default_advertised_address: ${default_advertised_address}"
    
    # Prepare neo4j.conf
    envsubst < conf.template > neo4j.conf.core-$ZONE

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

export initial_discovery_members=$(az network nic show -g $RESOURCE_GROUP -n cluster-nic-core1  --query ipConfigurations[].privateIpAddress -o tsv):5000,$(az network nic show -g $RESOURCE_GROUP -n cluster-nic-core2  --query ipConfigurations[].privateIpAddress -o tsv):5000,$(az network nic show -g $RESOURCE_GROUP -n cluster-nic-core3  --query ipConfigurations[].privateIpAddress -o tsv):5000
echo initial_discovery_members=$initial_discovery_members

ZONELIST='1 2 3'
for ZONE in $ZONELIST; do configureAndRestart "$ZONE" & done
wait