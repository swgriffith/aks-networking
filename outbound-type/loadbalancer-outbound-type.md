# Create AKS Cluster on Basic Infrastructure

This guide shows how to create an AKS cluster using Azure CLI on the basic infrastructure setup.

## Prerequisites

- Azure CLI installed and authenticated (`az login`)
- Appropriate Azure subscription permissions
- Basic infrastructure already deployed - See [Basic Infrastructure README](../basic/README.md)

## Deployment Steps

### 1. Get Infrastructure Outputs

Retrieve the subnet ID from the deployment:

```bash
RESOURCE_GROUP="rg-aks-networking-dev"
SUBNET_ID=$(az network vnet subnet show \
  --resource-group $RESOURCE_GROUP \
  --vnet-name vnet-aks-dev \
  --name aks-subnet \
  --query id -o tsv)
```

### 2. Create AKS Cluster

Create an AKS cluster with default options:

```bash
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name aks-basic-cluster \
  --vnet-subnet-id $SUBNET_ID \
  --network-plugin azure \
  --network-plugin-mode overlay \
  --service-cidr 172.16.0.0/16 \
  --dns-service-ip 172.16.0.10 \
  --node-vm-size Standard_DS4_v2 \
  --generate-ssh-keys
```

This creates an AKS cluster with:
- Default node count (3)
- VM size: Standard_DS4_v2
- System-assigned managed identity
- Default Kubernetes version
- Azure CNI Overlay networking
- Automatically generated SSH keys

### 3. Get Cluster Credentials

```bash
az aks get-credentials \
  --resource-group $RESOURCE_GROUP \
  --name aks-basic-cluster
```

### 4. Verify Cluster

```bash
kubectl get nodes
kubectl get pods -A
```

## Clean Up

### Delete AKS Cluster Only

```bash
az aks delete \
  --resource-group $RESOURCE_GROUP \
  --name aks-basic-cluster \
  --yes --no-wait
```

