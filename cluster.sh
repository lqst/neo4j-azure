#!/bin/bash
if [ -z $1 ] ; then
  echo "Usage: call me with resource group name"
  exit 1
fi
RESOURCE_GROUP=$1

export LOCATION="northeurope"
export RESOURCE_GROUP=$RESOURCE_GROUP
export VNET="vnet-neo4j-cc"
export SUBNET="subnet-client"
export SUBNET_CLUSTER="subnet-cluster"
export SECURITYGROUP="nsg-${SUBNET}"
export SECURITYGROUP_CLUSTER="nsg-${SUBNET_CLUSTER}"
export SSH_ALLOW_LIST="155.4.119.152"

# Create resource group
echo "Creating resource group $RESOURCE_GROUP in location $LOCATION" 
az group create --name $RESOURCE_GROUP --location $LOCATION


# Create client network security group
echo "Creating security group $SECURITYGROUP" 
az network nsg create \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --name $SECURITYGROUP

# Allow ssh from this computer to the client subnet
echo "Allow ssh for security group $SECURITYGROUP" 
az network nsg rule create \
    -g $RESOURCE_GROUP --nsg-name $SECURITYGROUP \
    -n allow_ssh --priority 100 \
    --source-address-prefixes $SSH_ALLOW_LIST \
    --source-port-ranges '*' \
    --destination-address-prefixes '*' \
    --destination-port-ranges 22 \
    --access Allow \
    --protocol Tcp --description "Accept ssh access from specified ip range"

# Create network security group for intra cluster communication
echo "Creating security group $SECURITYGROUP_CLUSTER" 
az network nsg create \
    --resource-group $RESOURCE_GROUP \
    --location $LOCATION \
    --name $SECURITYGROUP_CLUSTER   

# Create vnet
echo "Creating vnet $VNET and subnet $SUBNET" 
az network vnet create \
  --name $VNET \
  --resource-group $RESOURCE_GROUP \
  --network-security-group $SECURITYGROUP \
  --address-prefix 10.0.0.0/16 \
  --subnet-prefix 10.0.1.0/24 \
  --subnet-name $SUBNET

# Create additional subnet for intra cluster communication
az network vnet subnet create \
    --resource-group $RESOURCE_GROUP \
    --vnet-name $VNET \
    --name $SUBNET_CLUSTER \
    --network-security-group $SECURITYGROUP_CLUSTER \
    --address-prefix 10.0.2.0/24



listNode () {
    local ZONE=$1
    echo core-$ZONE PublicIp: $(az vm show -d -g $RESOURCE_GROUP -n core-$ZONE --query publicIps -o tsv) \
    client-nic: $(az network nic show -g $RESOURCE_GROUP -n client-nic-core$ZONE  --query ipConfigurations[].privateIpAddress -o tsv)  \
    cluster-nic: $(az network nic show -g $RESOURCE_GROUP -n cluster-nic-core$ZONE  --query ipConfigurations[].privateIpAddress -o tsv)
}

createNics () {
  local ZONE=$1
  export ZONE=$ZONE
  echo "zone-$ZONE start"

  # Create public ip address
  echo "core-$ZONE: Creating public ip address" 
  az network public-ip create -g $RESOURCE_GROUP -n public-ip-core-$ZONE --zone $ZONE --allocation-method Dynamic

  # Create NIC's
  # Add --accelerated-networking true if vm supports it
  echo "core-$ZONE: Creating NIC's" 
  az network nic create \
    --resource-group $RESOURCE_GROUP \
    --name cluster-nic-core$ZONE \
    --vnet-name $VNET \
    --subnet $SUBNET_CLUSTER \
    --internal-dns-name cluster-nic-core$ZONE \
    --network-security-group $SECURITYGROUP_CLUSTER

  az network nic create \
    --resource-group $RESOURCE_GROUP \
    --name client-nic-core$ZONE \
    --vnet-name $VNET \
    --subnet $SUBNET \
    --internal-dns-name client-nic-core$ZONE \
    --network-security-group $SECURITYGROUP \
    --public-ip-address public-ip-core-$ZONE
}

createNode () {
  local ZONE=$1
  export ZONE=$ZONE
  echo "zone-$ZONE start"

  # Create vm
  echo "core-$ZONE: Creating vm" 
  az vm create \
    --resource-group $RESOURCE_GROUP \
    --name core-$ZONE \
    --size Standard_DS1_v2\
    --image UbuntuLTS \
    --zone $ZONE \
    --admin-username azureuser \
    --nics client-nic-core$ZONE cluster-nic-core$ZONE \
    --ssh-key-value ~/.ssh/id_rsa.pub

    #--data-disk-sizes-gb
    #--encryption-at-host
    #--ephemeral-os-disk true \


    # Get internal ip address for cluster nic
    export cluster_nic_ip=$(az network nic show -g $RESOURCE_GROUP -n cluster-nic-core$ZONE  --query ipConfigurations[].privateIpAddress -o tsv)
    echo "core-$ZONE: cluster_nic_ip: ${cluster_nic_ip}"

    # Get internal ip address for client nic
    export client_nic_ip=$(az network nic show -g $RESOURCE_GROUP -n client-nic-core$ZONE  --query ipConfigurations[].privateIpAddress -o tsv)
    echo "core-$ZONE: client_nic_ip: ${client_nic_ip}"
    
    # Get public ip of the vm
    export default_advertised_address=$(az vm show -d -g $RESOURCE_GROUP -n core-$ZONE --query publicIps -o tsv)
    echo "core-$ZONE: default_advertised_address: ${default_advertised_address}"

    # Set up hosts
    # sudo apt-get install dnsmasq
    
    # Route
    # sudo ip route add 10.0.2.0 via 10.0.2.1 


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

# Create nics and public ip addresses
ZONELIST='1 2 3'
for ZONE in $ZONELIST; do createNics "$ZONE" & done
wait

export initial_discovery_members=$(az network nic show -g $RESOURCE_GROUP -n cluster-nic-core1  --query ipConfigurations[].privateIpAddress -o tsv):5000,$(az network nic show -g $RESOURCE_GROUP -n cluster-nic-core2  --query ipConfigurations[].privateIpAddress -o tsv):5000,$(az network nic show -g $RESOURCE_GROUP -n cluster-nic-core3  --query ipConfigurations[].privateIpAddress -o tsv):5000
echo initial_discovery_members=$initial_discovery_members

# Bring up the nodes
for ZONE in $ZONELIST; do createNode "$ZONE" & done
wait

# List core name and ip address
for ZONE in $ZONELIST; do listNode "$ZONE" & done
wait