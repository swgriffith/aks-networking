# Create AKS Cluster with Outbound Type Block

This guide shows how to create an AKS cluster with outbound type set to "block", which prevents all outbound internet connectivity from the cluster. This is similar to "none" but is explicitly blocking outbound traffic rather than simply not configuring it.

## Prerequisites

- Azure CLI installed and authenticated (`az login`)
- Appropriate Azure subscription permissions
- Infrastructure already deployed (basic or egress lockdown) - See [Infrastructure Setup](../README.md#infrastructure-setup-options)

## Deployment Steps

### 1. Get Infrastructure Outputs

For basic infrastructure:
```bash
RESOURCE_GROUP="rg-aks-networking-dev"
SUBNET_ID=$(az network vnet subnet show \
  --resource-group $RESOURCE_GROUP \
  --vnet-name vnet-aks-dev \
  --name aks-subnet \
  --query id -o tsv)
```

For egress lockdown infrastructure:
```bash
RESOURCE_GROUP="rg-aks-egress-lockdown-dev"
SUBNET_ID=$(az network vnet subnet show \
  --resource-group $RESOURCE_GROUP \
  --vnet-name vnet-aks-egress-dev \
  --name aks-subnet \
  --query id -o tsv)
```

### 2. Create AKS Cluster with Outbound Type Block

```bash
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name aks-block-cluster \
  --vnet-subnet-id $SUBNET_ID \
  --network-plugin azure \
  --network-plugin-mode overlay \
  --outbound-type block \
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
- **Blocked outbound internet connectivity**
- Automatically generated SSH keys

### 3. Configure Private Endpoints (Required)

Since outbound type is "block", you must configure private endpoints for all required Azure services:

```bash
# Example: Create private endpoint for Azure Container Registry
az network private-endpoint create \
  --name pe-acr \
  --resource-group $RESOURCE_GROUP \
  --vnet-name <vnet-name> \
  --subnet <subnet-name> \
  --private-connection-resource-id <acr-resource-id> \
  --group-id registry \
  --connection-name acr-connection

# Configure private DNS zone
az network private-dns zone create \
  --resource-group $RESOURCE_GROUP \
  --name privatelink.azurecr.io

az network private-dns link vnet create \
  --resource-group $RESOURCE_GROUP \
  --zone-name privatelink.azurecr.io \
  --name acr-dns-link \
  --virtual-network <vnet-name> \
  --registration-enabled false
```

Required private endpoints typically include:
- Azure Container Registry (for pulling images)
- Azure Key Vault (for secrets)
- Azure Storage (if using Azure Files/Disks)
- Any application-specific Azure services

### 4. Get Cluster Credentials

From your local machine (basic infrastructure):
```bash
az aks get-credentials \
  --resource-group $RESOURCE_GROUP \
  --name aks-block-cluster
```

From jump server (egress lockdown infrastructure):
```bash
# SSH to jump server first
JUMP_SERVER_IP=$(az vm show \
  --resource-group $RESOURCE_GROUP \
  --name vm-jump-server \
  --show-details \
  --query publicIps -o tsv)

ssh -i ~/.ssh/id_rsa_aks_jump azureuser@$JUMP_SERVER_IP

# Then on jump server
az login --identity
az aks get-credentials \
  --resource-group $RESOURCE_GROUP \
  --name aks-block-cluster
```

### 5. Verify Cluster

```bash
kubectl get nodes
kubectl get pods -A
```

## Differences Between Block and None

| Aspect | Block | None |
|--------|-------|------|
| **Status** | Deprecated (1.29+) | Current/Recommended |
| **Behavior** | Explicitly blocks outbound | No outbound configured |
| **Use Case** | Legacy/explicit blocking | Modern private clusters |
| **Future Support** | Being phased out | Actively supported |

**Recommendation**: For new deployments, use [outbound type "none"](none-outbound-type.md) instead.

## Important Considerations

### Image Management

With blocked outbound connectivity:

1. **Use Azure Container Registry with Private Endpoint**
```bash
# Import images from public registries
az acr import \
  --name <your-acr> \
  --source docker.io/library/nginx:latest \
  --image nginx:latest

az acr import \
  --name <your-acr> \
  --source mcr.microsoft.com/oss/kubernetes/pause:3.9 \
  --image pause:3.9
```

2. **Deploy images from private registry**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
spec:
  containers:
  - name: nginx
    image: <your-acr>.azurecr.io/nginx:latest
```

### DNS Configuration

Configure private DNS zones for all Azure services accessed via private endpoints:

```bash
# Common private DNS zones needed
privatelink.azurecr.io           # Container Registry
privatelink.vaultcore.azure.net  # Key Vault
privatelink.blob.core.windows.net # Storage
```

## Troubleshooting

### Nodes stuck in NotReady state

```bash
# Check node conditions
kubectl describe node <node-name>

# Common issues:
# - Cannot reach control plane
# - Cannot pull base images
# - DNS resolution failing
```

### Cannot pull images

```bash
# Verify ACR private endpoint
az network private-endpoint show \
  --resource-group $RESOURCE_GROUP \
  --name pe-acr

# Test DNS resolution from cluster
kubectl run -it --rm debug --image=busybox --restart=Never -- nslookup <your-acr>.azurecr.io
```

### Pods cannot reach Azure services

- Verify private endpoints exist for all required services
- Check private DNS zone links to your VNet
- Verify NSG rules allow traffic to private endpoint subnet
- Check firewall rules (if using egress lockdown infrastructure)

## Migration from Block to None

If you're using "block" and want to migrate to "none":

1. This cannot be changed on an existing cluster
2. You must create a new cluster with outbound type "none"
3. Migrate workloads to the new cluster
4. Decommission the old cluster

## Clean Up

### Delete AKS Cluster Only

```bash
az aks delete \
  --resource-group $RESOURCE_GROUP \
  --name aks-block-cluster \
  --yes --no-wait
```

### Delete Everything Including Infrastructure

```bash
az group delete --name $RESOURCE_GROUP --yes --no-wait
```

## Cost Considerations

- **Compute nodes**: Standard VM pricing applies
- **Standard_DS4_v2**: ~$175.20/month per node
- **Private Endpoints**: ~$7.30/month per endpoint + data processing
- **Private DNS Zones**: Minimal cost for queries
- **Load Balancer**: Internal only (lower cost than public)

> **Note**: Same cost structure as "none" outbound type.

## Next Steps

After deploying your AKS cluster with outbound type "block":
1. **Consider migrating to "none"** for future compatibility
2. Set up private endpoints for all required Azure services
3. Configure private DNS zones
4. Test image pull from private Azure Container Registry
5. Deploy applications that only use private connectivity
6. Plan migration strategy to "none" outbound type
