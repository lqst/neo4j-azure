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
export VM_NAME="neo4j_server"

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

# Create vnet
echo "Creating vnet $VNET and subnet $SUBNET" 
az network vnet create \
  --name $VNET \
  --resource-group $RESOURCE_GROUP \
  --network-security-group $SECURITYGROUP \
  --address-prefix 10.0.0.0/16 \
  --subnet-prefix 10.0.1.0/24 \
  --subnet-name $SUBNET

  echo "Creating vm" 
  az vm create \
    --resource-group $RESOURCE_GROUP \
    --name $VM_NAME \
    --size Standard_DS1_v2\
    --image UbuntuLTS \
    --zone 1 \
    --admin-username azureuser \
    --ssh-key-value ~/.ssh/id_rsa.pub

export external_ip=$(az vm show -d -g $RESOURCE_GROUP -n $VM_NAME --query publicIps -o tsv)
echo "external_ip: ${external_ip}"


# Install java
echo "Install java"
az vm run-command invoke -g $RESOURCE_GROUP -n $VM_NAME  --command-id RunShellScript \
    --scripts "sudo apt-get -y install openjdk-11-jre-headless"

# Add Neo4j gpg key
echo "Adding neo4j gpg key" 
az vm run-command invoke -g $RESOURCE_GROUP -n $VM_NAME  --command-id RunShellScript \
    --scripts "wget -O - https://debian.neo4j.com/neotechnology.gpg.key | sudo apt-key add - "
az vm run-command invoke -g $RESOURCE_GROUP -n $VM_NAME  --command-id RunShellScript \
    --scripts "echo 'deb https://debian.neo4j.com stable 4.3' | sudo tee -a /etc/apt/sources.list.d/neo4j.list"

# Accept Neo4j Enterprise licence agreement
echo "Accept Neo4j Enterprise licence agreement"
az vm run-command invoke -g $RESOURCE_GROUP -n $VM_NAME  --command-id RunShellScript \
    --scripts "echo 'neo4j-enterprise neo4j/question select I ACCEPT' | sudo debconf-set-selections"

az vm run-command invoke -g $RESOURCE_GROUP -n $VM_NAME  --command-id RunShellScript \
    --scripts "echo 'neo4j-enterprise neo4j/license note' | sudo debconf-set-selections"

# Upgrade packages
echo "Upgrade packages" 
az vm run-command invoke -g $RESOURCE_GROUP -n $VM_NAME  --command-id RunShellScript \
    --scripts "sudo apt-get update && sudo add-apt-repository universe"

# Install Neo4j Enterprise
echo "Installing Neo4j Enterprise" 
az vm run-command invoke -g $RESOURCE_GROUP -n $VM_NAME  --command-id RunShellScript \
    --scripts "sudo apt-get -y install neo4j-enterprise=1:4.3.3"


# Installing apoc
echo "Installing Apoc" 
az vm run-command invoke -g $RESOURCE_GROUP -n $VM_NAME  --command-id RunShellScript \
    --scripts "sudo wget https://github.com/neo4j-contrib/neo4j-apoc-procedures/releases/download/4.3.0.1/apoc-4.3.0.1-all.jar -O /var/lib/neo4j/plugins/apoc-full.jar"

# Change permssions for apoc jar
echo "apoc.jar permissions"
az vm run-command invoke -g $RESOURCE_GROUP -n $VM_NAME  --command-id RunShellScript \
    --scripts "sudo chown neo4j:adm /var/lib/neo4j/plugins/apoc-full.jar"


# Restart 
    az vm run-command invoke -g $RESOURCE_GROUP -n $VM_NAME  --command-id RunShellScript \
      --scripts "sudo systemctl restart neo4j"


### ### Changes to neo4 config file
### ###
### 
### 
### # Java Heap Size: by default the Java heap size is dynamically calculated based
### # on available system resources. Uncomment these lines to set specific initial
### # and maximum heap size.
### dbms.memory.heap.initial_size=10g
### dbms.memory.heap.max_size=10g
### 
### # The amount of memory to use for mapping the store files.
### # The default page cache memory assumes the machine is dedicated to running
### # Neo4j, and is heuristically set to 50% of RAM minus the Java heap size.
### dbms.memory.pagecache.size=16g
### 
### # With default configuration Neo4j only accepts local connections.
### # To accept non-local connections, uncomment this line:
### dbms.default_listen_address=0.0.0.0
### 
### # The address at which this server can be reached by its clients. This may be the server's IP address or DNS name, or
### # it may be the address of a reverse proxy which sits in front of the server. This setting may be overridden for
### # individual connectors below.
### dbms.default_advertised_address=[insert fqdn here] 
### 
### ###
### 
### Default locations
### home:         /var/lib/neo4j
### config:       /etc/neo4j
### logs:         /var/log/neo4j
### plugins:      /var/lib/neo4j/plugins
### import:       /var/lib/neo4j/import
### data:         /var/lib/neo4j/data
### certificates: /var/lib/neo4j/certificates
### licenses:     /var/lib/neo4j/licenses
### run:          /var/run/neo4j


