# Having fun with Azure CLI

I thought it would be a fun excercise to set up  a Neo4j Enterprise Edition Causal Cluster on Azure using the Azure CLI. Also, I wanted to have full control of setting up the network, vm's and installation/configuration of Neo4j.

The public ip:s assigned are only used for ssh. The neo4j cluster in currently only reachable within the client-subnet.

**Disclamer** Use at own risk. These are my personal experiments, thoughts and oppinions.

## Before you start
Login to azure
```shell
az login
```

Note: The scripts assumes that there is a public key `~/.ssh/id_rsa.pub` and private key  `~/.ssh/id_rsa`



## Create new cluster
Creates a new resource group `rg-neo4j-cluster`. Creates vnet/subnet and a neo4j cluster.
```shell
sh cluster.sh rg-neo4j-cluster
```

## Update configuration and restart
```shell
sh conf.sh rg-neo4j-cluster
```

## Clean up 
Remove everything in the resource group rg-neo4j-cluster `<RESOURCE_GROUP>`
```shell
sh remove.sh rg-neo4j-cluster
```

## SSH 
```shell
ssh -i ~/.ssh/id_rsa azureuser@52.138.145.31
```



## Todo
- [ ] Kill forks when terminating script
- [ ] Document and comment every step
- [ ] Create network diagram
- [ ] Set database admin credentials (currently neo4/neo4j + change on first login)
- [x] Add additional NIC and configure neo4j to avoid copetition between intra cluster communication and clients
- [ ] Add intra cluster encryption
- [ ] Add VPN or SSL/TLS for client traffic
- [ ] Enable encryption at rest for azure vm's
- [ ] Add script for rolling upgrade
- [ ] Add script for rolling config change
- [ ] Add script for adding read replica