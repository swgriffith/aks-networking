# Create AKS Cluster with Outbound Type None

This guide shows how to create an AKS cluster with outbound type set to "none", which disables all outbound internet connectivity from the cluster. This configuration is typically used for air-gapped environments or scenarios where all communication happens through private endpoints.

> **Important:** The `none` outbound type only works in network isolated clusters and requires an Azure Container Registry (ACR) configured with Microsoft Container Registry (MCR) pull-through cache to pull container images.

## Prerequisites

- Azure CLI installed and authenticated (`az login`)
- Appropriate Azure subscription permissions
- Infrastructure already deployed (basic or egress lockdown) - See [Infrastructure Setup](../README.md#infrastructure-setup-options)
- **Network isolated environment** (no internet egress)
- **Azure Container Registry with MCR pull-through cache configured** (required for pulling container images)

## Use Cases

Use outbound type "none" when:
- Running in fully air-gapped or disconnected environments
- All Azure services are accessed through private endpoints
- Strict compliance requirements prohibit any internet egress
- Workloads only communicate within the VNet or through ExpressRoute/VPN

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
CLUSTER_IDENTITY_NAME="id-aks-none-cluster"
az identity create \
  --name $CLUSTER_IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP

CLUSTER_IDENTITY_RESOURCE_ID=$(az identity show \
  --name $CLUSTER_IDENTITY_NAME \
  --resource-group $RESOURCE_GROUP \
  --query 'id' -o tsv)

# Create kubelet identity
KUBELET_IDENTITY_NAME="id-aks-none-kubelet"
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

### 6. Create AKS Cluster with Outbound Type None

```bash
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name aks-none-cluster \
  --vnet-subnet-id $SUBNET_ID \
  --assign-identity $CLUSTER_IDENTITY_RESOURCE_ID \
  --assign-kubelet-identity $KUBELET_IDENTITY_RESOURCE_ID \
  --bootstrap-artifact-source Cache \
  --bootstrap-container-registry-resource-id $REGISTRY_ID \
  --network-plugin azure \
  --network-plugin-mode overlay \
  --outbound-type none \
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
- **No outbound internet connectivity**
- Bootstrap artifact source set to Cache (uses private ACR)
- Automatically generated SSH keys

### 7. Configure Additional Private Endpoints (Optional)

You may also need private endpoints for:
- Azure Key Vault (for secrets)
- Azure Storage (if using Azure Files/Disks)
- Any application-specific Azure services

### 8. Get Cluster Credentials

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
  --name aks-none-cluster
```

### 9. Verify Cluster

```bash
kubectl get nodes
kubectl get pods -A
```

## Important Considerations

### Image Pull Strategy

With no outbound connectivity, you cannot pull images from public registries. Options include:

1. **Use Azure Container Registry with Private Endpoint**
```bash
# Import images to ACR
az acr import \
  --name <your-acr> \
  --source docker.io/library/nginx:latest \
  --image nginx:latest
```

2. **Pre-cache images on nodes** - Not recommended for production

### DNS Configuration

Ensure DNS resolution works for private endpoints:

```bash
# Configure private DNS zones for Azure services
az network private-dns zone create \
  --resource-group $RESOURCE_GROUP \
  --name privatelink.azurecr.io
```

### Azure Monitor and Logging

Configure Azure Monitor for containers to use private endpoints or disable if not needed.

## Troubleshooting

### Nodes not ready

```bash
# Check node status
kubectl get nodes -o wide

# Check events
kubectl get events --all-namespaces --sort-by='.lastTimestamp'

# Common issue: Cannot pull images
kubectl describe pod <pod-name> -n <namespace>
```

### Cannot pull images

Verify private endpoint connectivity:
```bash
# Test from a node
kubectl debug node/<node-name> -it --image=busybox
# Then inside the debug pod
nslookup <your-acr>.azurecr.io
```

### Pods cannot reach Azure services

- Verify private endpoints are created for all required services
- Check private DNS zone configuration
- Verify NSG rules allow traffic to private endpoints

## Clean Up

### Delete AKS Cluster Only

```bash
az aks delete \
  --resource-group $RESOURCE_GROUP \
  --name aks-none-cluster \
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

> **Note**: While there's no egress data cost, private endpoint costs can add up with multiple services.

## Next Steps

After deploying your AKS cluster with outbound type "none":
1. Set up private endpoints for all required Azure services
2. Configure private DNS zones
3. Test image pull from private Azure Container Registry
4. Deploy applications that only use private connectivity
5. Configure monitoring through private endpoints
6. Document private endpoint architecture for your team
