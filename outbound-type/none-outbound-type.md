# Create AKS Cluster with Outbound Type None

This guide shows how to create an AKS cluster with outbound type set to "none", which disables all outbound internet connectivity from the cluster. This configuration is typically used for air-gapped environments or scenarios where all communication happens through private endpoints.

## Prerequisites

- Azure CLI installed and authenticated (`az login`)
- Appropriate Azure subscription permissions
- Infrastructure already deployed (basic or egress lockdown) - See [Infrastructure Setup](../README.md#infrastructure-setup-options)

## Use Cases

Use outbound type "none" when:
- Running in fully air-gapped or disconnected environments
- All Azure services are accessed through private endpoints
- Strict compliance requirements prohibit any internet egress
- Workloads only communicate within the VNet or through ExpressRoute/VPN

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

### 2. Create AKS Cluster with Outbound Type None

```bash
az aks create \
  --resource-group $RESOURCE_GROUP \
  --name aks-none-cluster \
  --vnet-subnet-id $SUBNET_ID \
  --network-plugin azure \
  --outbound-type none \
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
- **No outbound internet connectivity**
- Automatically generated SSH keys

### 3. Configure Private Endpoints (Required)

Since outbound type is "none", you must configure private endpoints for all required Azure services:

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
  --name aks-none-cluster
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
  --name aks-none-cluster
```

### 5. Verify Cluster

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
