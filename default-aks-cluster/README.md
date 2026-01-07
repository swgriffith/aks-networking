# Create AKS Cluster with Azure CLI

This guide shows how to create an AKS cluster using Azure CLI with default options on both the basic infrastructure and egress lockdown infrastructure.

## Prerequisites

- Azure CLI installed and authenticated (`az login`)
- Appropriate Azure subscription permissions
- Infrastructure already deployed:
  - For basic infrastructure: See [Basic Infrastructure README](../basic/README.md)
  - For egress lockdown infrastructure: See [Egress Lockdown README](../egress-lockdown/README.md)

## Option 1: Basic Infrastructure

Create an AKS cluster using the basic infrastructure with all default options.

> **Note**: Ensure you've deployed the basic infrastructure first. See [Basic Infrastructure README](../basic/README.md) for deployment instructions.

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

### 3. Create AKS Cluster with Default Options

Create an AKS cluster with all default options:

```bash
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name aks-basic-cluster \
  --vnet-subnet-id $SUBNET_ID \
  --network-plugin azure \
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
- Azure CNI networking
- Automatically generated SSH keys

### 4. Get Cluster Credentials

```bash
az aks get-credentials \
  --resource-group $RESOURCE_GROUP \
  --name aks-basic-cluster
```

### 5. Verify Cluster

```bash
kubectl get nodes
kubectl get pods -A
```

## Option 2: Egress Lockdown Infrastructure

Create an AKS cluster using the egress lockdown infrastructure with Azure Firewall.

> **Note**: Ensure you've deployed the egress lockdown infrastructure first. See [Egress Lockdown README](../egress-lockdown/README.md) for deployment instructions.

### 1. Get Infrastructure Outputs

Retrieve the subnet ID and firewall private IP:

```bash
RESOURCE_GROUP="rg-aks-egress-lockdown-dev"
SUBNET_ID=$(az network vnet subnet show \
  --resource-group $RESOURCE_GROUP \
  --vnet-name vnet-aks-egress-dev \
  --name aks-subnet \
  --query id -o tsv)

FIREWALL_IP=$(az network firewall show \
  --resource-group $RESOURCE_GROUP \
  --name afw-aks-dev \
  --query ipConfigurations[0].privateIPAddress -o tsv)
```

### 3. Create AKS Cluster with Outbound Type UDR

Create an AKS cluster that uses the User Defined Route (UDR) for egress traffic:

```bash
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name aks-egress-cluster \
  --vnet-subnet-id $SUBNET_ID \
  --network-plugin azure \
  --outbound-type userDefinedRouting \
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
- Azure CNI networking
- User Defined Routing for egress traffic (routes through Azure Firewall)
- Automatically generated SSH keys

### 4. Connect to Jump Server

Since this is a private cluster setup, you'll need to use the jump server to access kubectl:

```bash
# Get the jump server public IP
JUMP_SERVER_IP=$(az vm show \
  --resource-group $RESOURCE_GROUP \
  --name vm-jump-server \
  --show-details \
  --query publicIps -o tsv)

# SSH to jump server
ssh -i ~/.ssh/id_rsa_aks_jump azureuser@$JUMP_SERVER_IP
```

### 3. Get Cluster Credentials on Jump Server

Once connected to the jump server, get the cluster credentials:

```bash
# Install Azure CLI (if not already done via cloud-init)
# This step may not be needed as cloud-init installs it

# Login to Azure
az login --identity

# Get AKS credentials
az aks get-credentials \
  --resource-group rg-aks-egress-lockdown-dev \
  --name aks-egress-cluster
```
4
### 5. Verify Cluster

```bash
kubectl get nodes
kubectl get pods -A
```

## Clean Up

### Delete AKS Cluster Only

```bash
az aks delete \
  --resource-group $RESOURCE_GROUP \
  --name aks-cluster \
  --yes --no-wait
```

### Delete Everything Including Infrastructure

Basic infrastructure:
```bash
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

Egress lockdown infrastructure:
```bash
az group delete --name $RESOURCE_GROUP --yes --no-wait
```
