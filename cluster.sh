#!/bin/bash
if [ -z $1 ] ; then
  echo "Usage: call me with resource group name"
  exit 1
fi
RESOURCE_GROUP=$1

export LOCATION="northeurope"
export RESOURCE_GROUP=$RESOURCE_GROUP
export VNET="vnet-cluster"
export SUBNET="subnet-cluster"
export SECURITYGROUP="nsg-${SUBNET}"
export SSH_ALLOW_LIST="155.4.119.152"

# Create resource group
echo "Creating resource group $RESOURCE_GROUP in location $LOCATION" 
az group create --name $RESOURCE_GROUP --location $LOCATION

# Create virtual subnet
echo "Creating vnet $VNET and subnet $SUBNET" 
az network vnet create \
  --name $VNET \
  --resource-group $RESOURCE_GROUP \
  --subnet-name $SUBNET

# Create network security group
echo "Creating security group $SECURITYGROUP" 
az network nsg create \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --name $SECURITYGROUP

# Allow ssh from this computer to the subnet
az network nsg rule create \
    -g $RESOURCE_GROUP --nsg-name $SECURITYGROUP \
    -n allow_ssh --priority 100 \
    --source-address-prefixes $SSH_ALLOW_LIST \
    --source-port-ranges '*' \
    --destination-address-prefixes '*' \
    --destination-port-ranges 22 \
    --access Allow \
    --protocol Tcp --description "Accept ssh access from specified ip range"

# Allow ssh from this computer to the subnet
az network nsg rule create \
    -g $RESOURCE_GROUP --nsg-name $SECURITYGROUP \
    -n allow_ssh --priority 100 \
    --source-address-prefixes $SSH_ALLOW_LIST \
    --source-port-ranges '*' \
    --destination-address-prefixes '*' \
    --destination-port-ranges 22 \
    --access Allow \
    --protocol Tcp --description "Accept ssh access from specified ip range"

# Update virtual subnet with sequrity group
az network vnet subnet update \
    --resource-group $RESOURCE_GROUP \
    --vnet-name $VNET \
    --name $SUBNET \
    --network-security-group $SECURITYGROUP


listNode () {
    local ZONE=$1
    IP=$ZONE $(az vm show -d -g $RESOURCE_GROUP -n core-$ZONE --query publicIps -o tsv)
    echo "core-$ZONE: $IP"
}

createNode () {
  local ZONE=$1
  echo "zone-$ZONE start"
  # Create vm
  echo "core-$ZONE: Creating vm" 
  az vm create \
    --resource-group $RESOURCE_GROUP \
    --name core-$ZONE \
    --size Standard_DS1_v2\
    --image UbuntuLTS \
    --vnet-name $VNET \
    --subnet $SUBNET \
    --zone $ZONE \
    --admin-username azureuser \
    --ssh-key-value ~/.ssh/id_rsa.pub

    # Get public ip of the vm
    export default_advertised_address=$(az vm show -d -g $RESOURCE_GROUP -n core-$ZONE --query publicIps -o tsv)
    echo "core-$ZONE: default_advertised_address: ${default_advertised_address}"

    # Prepare neo4j.conf
    envsubst < conf.template > neo4j.conf.core-$ZONE

    # Make sure /etc/neo4j/ path exists
    echo "core-$ZONE: Ensure path /etc/neo4j/ path exists"
    az vm run-command invoke -g $RESOURCE_GROUP -n core-$ZONE  --command-id RunShellScript \
      --scripts "sudo mkdir -p /etc/neo4j"

    # "Copy" neo4j.conf to vm
    # Encode it
    base64 -i neo4j.conf.core-$ZONE -o neo4j.conf.core-$ZONE.base64
    export NEO4J_ENCODED_CONF=$(cat neo4j.conf.core-$ZONE.base64)

    # Decode it
    echo "core-$ZONE: Add neo4j.conf"
    az vm run-command invoke -g $RESOURCE_GROUP -n core-$ZONE  --command-id RunShellScript \
      --scripts "sudo echo ${NEO4J_ENCODED_CONF} | base64 -d > /etc/neo4j/neo4j.conf"


    # Install java
    echo "core-$ZONE: Install java"
    az vm run-command invoke -g $RESOURCE_GROUP -n core-$ZONE  --command-id RunShellScript \
      --scripts "sudo apt-get -y install openjdk-11-jre-headless"

    # Add Neo4j gpg key
    echo "core-$ZONE: Adding neo4j gpg key" 
    az vm run-command invoke -g $RESOURCE_GROUP -n core-$ZONE  --command-id RunShellScript \
      --scripts "wget -O - https://debian.neo4j.com/neotechnology.gpg.key | sudo apt-key add - "
    az vm run-command invoke -g $RESOURCE_GROUP -n core-$ZONE  --command-id RunShellScript \
      --scripts "echo 'deb https://debian.neo4j.com stable 4.2' | sudo tee -a /etc/apt/sources.list.d/neo4j.list"

    # Accept Neo4j Enterprise licence agreement
    echo "core-$ZONE: Accept Neo4j Enterprise licence agreement"
    az vm run-command invoke -g $RESOURCE_GROUP -n core-$ZONE  --command-id RunShellScript \
      --scripts "echo 'neo4j-enterprise neo4j/question select I ACCEPT' | sudo debconf-set-selections"
    az vm run-command invoke -g $RESOURCE_GROUP -n core-$ZONE  --command-id RunShellScript \
      --scripts "echo 'neo4j-enterprise neo4j/license note' | sudo debconf-set-selections"

    # Upgrade packages
    echo "core-$ZONE: Upgrade packages" 
    az vm run-command invoke -g $RESOURCE_GROUP -n core-$ZONE  --command-id RunShellScript \
      --scripts "sudo apt-get update && sudo add-apt-repository universe"

    # Install Neo4j Enterprise
    echo "core-$ZONE: Installing Neo4j Enterprise" 
    az vm run-command invoke -g $RESOURCE_GROUP -n core-$ZONE  --command-id RunShellScript \
      --scripts "sudo apt-get -o Dpkg::Options::='--force-confold' -y install neo4j-enterprise=1:4.2.2"
}

export initial_discovery_members=core-1:5000,core-2:5000,core-3:5000

# Bring up the nodes
ZONELIST='1 2 3'
for ZONE in $ZONELIST; do createNode "$ZONE" & done
wait

# List core name and ip address
for ZONE in $ZONELIST; do listNode "$ZONE" & done
wait