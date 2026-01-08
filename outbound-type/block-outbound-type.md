# Create AKS Cluster with Outbound Type Block

This guide shows how to create an AKS cluster with outbound type set to "block", which prevents all outbound internet connectivity from the cluster. This is similar to "none" but is explicitly blocking outbound traffic rather than simply not configuring it.

> **Important:** The `block` outbound type only works in network isolated clusters and requires an Azure Container Registry (ACR) configured with Microsoft Container Registry (MCR) pull-through cache to pull container images.

## Prerequisites

- Azure CLI installed and authenticated (`az login`)
- Appropriate Azure subscription permissions
- Infrastructure already deployed (basic or egress lockdown) - See [Infrastructure Setup](../README.md#infrastructure-setup-options)
- **Network isolated environment** (no internet egress)
- **Azure Container Registry with MCR pull-through cache configured** (required for pulling container images)

## Deployment Steps

### 1. Get Infrastructure Outputs

```bash
RESOURCE_GROUP="rg-aks-egress-lockdown-dev"
VNET_NAME="vnet-aks-egress-dev"
SUBNET_ID=$(az network vnet subnet show \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --name aks-subnet \
  --query id -o tsv)
```

### 2. Configure Azure Container Registry with MCR Pull-Through Cache

> **Important:** The ACR must be created and configured BEFORE creating the AKS cluster.

```bash
# Set ACR name (must be globally unique)
REGISTRY_NAME="<your-acr-name>"

# Create Azure Container Registry with Premium SKU (required for pull-through cache)
az acr create \
  --resource-group $RESOURCE_GROUP \
  --name $REGISTRY_NAME \
  --sku Premium \
  --public-network-enabled false

REGISTRY_ID=$(az acr show --name $REGISTRY_NAME -g $RESOURCE_GROUP --query 'id' --output tsv)

# Enable MCR pull-through cache (cache rule name must be exactly as shown)
az acr cache create \
  -n aks-managed-mcr \
  -r $REGISTRY_NAME \
  -g $RESOURCE_GROUP \
  --source-repo "mcr.microsoft.com/*" \
  --target-repo "aks-managed-repository/*"
```

> **Note:** The cache rule name `aks-managed-mcr` and target repo `aks-managed-repository/*` are required for AKS network isolated clusters.

### 3. Create Private Endpoint for ACR

```bash
# Create private endpoint for ACR
az network private-endpoint create \
  --name pe-acr \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --subnet aks-subnet \
  --private-connection-resource-id $REGISTRY_ID \
  --group-id registry \
  --connection-name acr-connection

# Get private endpoint IP addresses
NETWORK_INTERFACE_ID=$(az network private-endpoint show \
  --name pe-acr \
  --resource-group $RESOURCE_GROUP \
  --query 'networkInterfaces[0].id' \
  --output tsv)

REGISTRY_PRIVATE_IP=$(az network nic show \
  --ids $NETWORK_INTERFACE_ID \
  --query "ipConfigurations[?privateLinkConnectionProperties.requiredMemberName=='registry'].privateIPAddress" \
  --output tsv)

LOCATION=$(az group show --name $RESOURCE_GROUP --query location -o tsv)
DATA_ENDPOINT_PRIVATE_IP=$(az network nic show \
  --ids $NETWORK_INTERFACE_ID \
  --query "ipConfigurations[?privateLinkConnectionProperties.requiredMemberName=='registry_data_$LOCATION'].privateIPAddress" \
  --output tsv)
```

### 4. Configure Private DNS Zone for ACR

```bash
# Create private DNS zone
az network private-dns zone create \
  --resource-group $RESOURCE_GROUP \
  --name "privatelink.azurecr.io"

# Link DNS zone to VNet
az network private-dns link vnet create \
  --resource-group $RESOURCE_GROUP \
  --zone-name "privatelink.azurecr.io" \
  --name acr-dns-link \
  --virtual-network $VNET_NAME \
  --registration-enabled false

# Add A record for registry endpoint
az network private-dns record-set a create \
  --name $REGISTRY_NAME \
  --zone-name "privatelink.azurecr.io" \
  --resource-group $RESOURCE_GROUP

az network private-dns record-set a add-record \
  --record-set-name $REGISTRY_NAME \
  --zone-name "privatelink.azurecr.io" \
  --resource-group $RESOURCE_GROUP \
  --ipv4-address $REGISTRY_PRIVATE_IP

# Add A record for data endpoint
az network private-dns record-set a create \
  --name $REGISTRY_NAME.$LOCATION.data \
  --zone-name "privatelink.azurecr.io" \
  --resource-group $RESOURCE_GROUP

az network private-dns record-set a add-record \
  --record-set-name $REGISTRY_NAME.$LOCATION.data \
  --zone-name "privatelink.azurecr.io" \
  --resource-group $RESOURCE_GROUP \
  --ipv4-address $DATA_ENDPOINT_PRIVATE_IP
```

### 5. Create Managed Identities for AKS Cluster

```bash
# Create control plane identity
CLUSTER_IDENTITY_NAME="id-aks-block-cluster"
az identity create \
  --name $CLUSTER_IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP

CLUSTER_IDENTITY_RESOURCE_ID=$(az identity show \
  --name $CLUSTER_IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP \
  --query 'id' -o tsv)

# Create kubelet identity
KUBELET_IDENTITY_NAME="id-aks-block-kubelet"
az identity create \
  --name $KUBELET_IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP

KUBELET_IDENTITY_RESOURCE_ID=$(az identity show \
  --name $KUBELET_IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP \
  --query 'id' -o tsv)

KUBELET_IDENTITY_PRINCIPAL_ID=$(az identity show \
  --name $KUBELET_IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP \
  --query 'principalId' -o tsv)

# Grant AcrPull permission to kubelet identity
az role assignment create \
  --role AcrPull \
  --scope $REGISTRY_ID \
  --assignee-object-id $KUBELET_IDENTITY_PRINCIPAL_ID \
  --assignee-principal-type ServicePrincipal
```

### 6. Create API Server Subnet

```bash
# Create subnet for API server VNet integration
az network vnet subnet create \
  --name apiserver-subnet \
  --vnet-name $VNET_NAME \
  --resource-group $RESOURCE_GROUP \
  --address-prefixes 10.0.3.0/28

APISERVER_SUBNET_ID=$(az network vnet subnet show \
  --resource-group $RESOURCE_GROUP \
  --vnet-name $VNET_NAME \
  --name apiserver-subnet \
  --query id -o tsv)

# Grant Network Contributor role to cluster identity on API server subnet
CLUSTER_IDENTITY_PRINCIPAL_ID=$(az identity show \
  --name $CLUSTER_IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP \
  --query 'principalId' -o tsv)

az role assignment create \
  --scope $APISERVER_SUBNET_ID \
  --role "Network Contributor" \
  --assignee-object-id $CLUSTER_IDENTITY_PRINCIPAL_ID \
  --assignee-principal-type ServicePrincipal
```

### 7. Create AKS Cluster with Outbound Type Block

```bash
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name aks-block-cluster \
  --vnet-subnet-id $SUBNET_ID \
  --assign-identity $CLUSTER_IDENTITY_RESOURCE_ID \
  --assign-kubelet-identity $KUBELET_IDENTITY_RESOURCE_ID \
  --bootstrap-artifact-source Cache \
  --bootstrap-container-registry-resource-id $REGISTRY_ID \
  --network-plugin azure \
  --network-plugin-mode overlay \
  --outbound-type block \
  --enable-private-cluster \
  --enable-apiserver-vnet-integration \
  --apiserver-subnet-id $APISERVER_SUBNET_ID \
  --service-cidr 172.16.0.0/16 \
  --dns-service-ip 172.16.0.10 \
  --node-vm-size Standard_DS4_v2 \
  --generate-ssh-keys
```

This creates an AKS cluster with:
- Default Kubernetes version
- VM size: Standard_DS4_v2
- Custom managed identities (control plane and kubelet)
- Azure CNI Overlay networking
- **Private cluster with API server VNet integration** (required for block outbound type)
- **Blocked outbound internet connectivity**
- Bootstrap artifact source set to Cache (uses private ACR)
- Automatically generated SSH keys

### 8. Configure Additional Private Endpoints (Optional)

You may also need private endpoints for:
- Azure Key Vault (for secrets)
- Azure Storage (if using Azure Files/Disks)
- Any application-specific Azure services

### 9. Get Cluster Credentials

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

### 10. Verify Cluster

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
