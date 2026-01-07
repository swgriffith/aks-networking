# Basic AKS Infrastructure

This deployment creates the baseline infrastructure for an AKS cluster:
- Resource Group
- Virtual Network
- Subnet for AKS nodes

## Architecture

A simple network topology with a single subnet for AKS nodes. Internet egress uses Azure's default routing.

```
┌─────────────────────────────────────────────────────┐
│ Virtual Network (10.0.0.0/16)                       │
│                                                      │
│  ┌────────────────────────────┐                     │
│  │ AKS Subnet (10.0.0.0/24)   │                     │
│  │                             │                     │
│  │ ┌────────┐  ┌────────┐     │                     │
│  │ │ Node 1 │  │ Node 2 │     │                     │
│  │ └───┬────┘  └───┬────┘     │                     │
│  └──────┼──────────┼──────────┘                     │
│         │          │                                 │
│         ▼          ▼                                 │
│    Default Azure Routing                            │
│                                                      │
└───────────────┬──────────────────────────────────────┘
                │
                ▼
           Internet
```

## Resources Created

- **Resource Group**: Container for all AKS-related resources
- **Virtual Network**: Network isolation for the AKS cluster
- **AKS Subnet**: Dedicated subnet for AKS node pools

## Prerequisites

- Azure CLI installed
- Bicep CLI installed
- Azure subscription with appropriate permissions

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `resourceGroupName` | string | `rg-aks-networking-dev` | Name of the resource group |
| `location` | string | `eastus` | Azure region for resources |
| `vnetName` | string | `vnet-aks-dev` | Name of the virtual network |
| `vnetAddressPrefix` | string | `10.0.0.0/16` | Address space for the VNet |
| `aksSubnetName` | string | `aks-subnet` | Name of the AKS subnet |
| `aksSubnetAddressPrefix` | string | `10.0.0.0/24` | Address prefix for AKS subnet |
| `tags` | object | See main.bicepparam | Tags to apply to resources |

## Deployment

### Using Azure CLI with parameters file

```bash
az deployment sub create \
  --location eastus \
  --template-file main.bicep \
  --parameters main.bicepparam
```

### Using Azure CLI with environment variables

First, set the environment variables:

```bash
export RESOURCE_GROUP_NAME="rg-aks-networking-dev"
export LOCATION="eastus"
export VNET_NAME="vnet-aks-dev"
export VNET_ADDRESS_PREFIX="10.0.0.0/16"
export AKS_SUBNET_NAME="aks-subnet"
export AKS_SUBNET_ADDRESS_PREFIX="10.0.0.0/24"
export ENVIRONMENT="Dev"
export PROJECT="AKS-Networking"
```

Then deploy:

```bash
az deployment sub create \
  --location $LOCATION \
  --template-file main.bicep \
  --parameters resourceGroupName=$RESOURCE_GROUP_NAME \
               location=$LOCATION \
               vnetName=$VNET_NAME \
               vnetAddressPrefix=$VNET_ADDRESS_PREFIX \
               aksSubnetName=$AKS_SUBNET_NAME \
               aksSubnetAddressPrefix=$AKS_SUBNET_ADDRESS_PREFIX \
               tags="{\"Environment\":\"$ENVIRONMENT\",\"Project\":\"$PROJECT\",\"ManagedBy\":\"Bicep\"}"
```

### Using Azure CLI with inline parameters (without environment variables)

```bash
az deployment sub create \
  --location eastus \
  --template-file main.bicep \
  --parameters resourceGroupName=rg-aks-demo \
               location=eastus \
               vnetName=vnet-aks-demo \
               vnetAddressPrefix=10.0.0.0/16 \
               aksSubnetName=aks-subnet \
               aksSubnetAddressPrefix=10.0.0.0/24
```

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| `resourceGroupId` | string | Resource ID of the resource group |
| `resourceGroupName` | string | Name of the resource group |
| `vnetId` | string | Resource ID of the virtual network |
| `vnetName` | string | Name of the virtual network |
| `aksSubnetId` | string | Resource ID of the AKS subnet |
| `aksSubnetName` | string | Name of the AKS subnet |

## Cost Considerations

This basic infrastructure has minimal costs:
- **Virtual Network**: No charge for VNet and subnets
- **Resource Group**: No charge
- **Estimated Monthly Cost**: ~$0

> **Note**: Costs shown don't include AKS cluster costs. Actual costs begin when you deploy an AKS cluster.

## Security Best Practices

1. **Network Security Groups (NSGs)**: Consider adding NSGs to the AKS subnet for traffic filtering
2. **Private AKS Cluster**: For production, consider deploying a private AKS cluster
3. **Azure Policy**: Implement Azure Policy for governance and compliance
4. **Diagnostic Logs**: Enable diagnostic settings for the VNet when needed

## Next Steps

After deploying this baseline infrastructure, you can:
1. Deploy an AKS cluster into the created subnet
2. Add additional subnets for other services (e.g., Azure Firewall, Application Gateway)
3. Configure network security groups and route tables
4. Set up peering with other virtual networks

## Troubleshooting

### Deployment fails with "ResourceGroupNotFound"
- Ensure you're deploying at subscription scope (`deployment sub create`)
- The template creates the resource group; don't create it manually first

### Cannot deploy AKS cluster into subnet
- Verify the subnet ID from the deployment outputs
- Ensure the subnet has sufficient IP addresses for your node count
- Check that no conflicting resources exist in the subnet

### VNet peering issues
- Verify both VNets don't have overlapping address spaces
- Ensure proper permissions on both subscriptions if cross-subscription peering

## Clean Up

To delete all resources:

```bash
az group delete --name rg-aks-networking-dev --yes --no-wait
```

> **Note**: Resource deletion typically completes in a few minutes.
