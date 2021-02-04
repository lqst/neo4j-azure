# Having fun with Azure CLI

I thought it would be a fun excercise to set up  a Neo4j Enterprise Edition Causal Cluster on Azure using the Azure CLI. Also, I wanted to have full control of setting up the network, vm's and installation/configuration of Neo4j.

**Disclamer** Use at own risk. These are my personal experiments, thoughts and oppinions.

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


## Todo
- [ ] Document and comment every step
- [ ] Create network diagram
- [ ] Add additional NIC's and configure neo4j to avoid copetition between intra cluster communication, backups and clients
- [ ] Add intra cluster encryption
- [ ] Add VPN or SSL/TLS for client traffic
- [ ] Enable encryption at rest for azure vm's
- [ ] Add script for rolling upgrade
- [ ] Add script for rolling config change