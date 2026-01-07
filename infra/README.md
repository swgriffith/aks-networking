# AKS Networking Infrastructure Deployments

This directory contains Bicep templates for deploying AKS networking infrastructure with different configurations.

## Deployment Scenarios

### 1. Basic Infrastructure (`basic/`)

A baseline deployment with:
- Resource Group
- Virtual Network
- Subnet for AKS nodes

[View detailed documentation](basic/README.md)

### 2. Egress Lockdown (`egress-lockdown/`)

A secure deployment with egress traffic control:
- Resource Group
- Virtual Network with AKS and Firewall subnets
- Azure Firewall
- Route Table forcing all egress traffic through firewall

[View detailed documentation](egress-lockdown/README.md)

---

## Quick Start - Basic Infrastructure

### Set Environment Variables

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

### Deploy

```bash
cd basic

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

---

## Quick Start - Egress Lockdown

### Set Environment Variables

```bash
export RESOURCE_GROUP_NAME="rg-aks-egress-lockdown-dev"
export LOCATION="eastus"
export VNET_NAME="vnet-aks-egress-dev"
export VNET_ADDRESS_PREFIX="10.0.0.0/16"
export AKS_SUBNET_NAME="aks-subnet"
export AKS_SUBNET_ADDRESS_PREFIX="10.0.0.0/24"
export FIREWALL_SUBNET_ADDRESS_PREFIX="10.0.1.0/26"
export FIREWALL_NAME="afw-aks-dev"
export ROUTE_TABLE_NAME="rt-aks-egress-dev"
export ENVIRONMENT="Dev"
export PROJECT="AKS-Networking"
```

### Deploy

```bash
cd egress-lockdown

az deployment sub create \
  --location $LOCATION \
  --template-file main.bicep \
  --parameters resourceGroupName=$RESOURCE_GROUP_NAME \
               location=$LOCATION \
               vnetName=$VNET_NAME \
               vnetAddressPrefix=$VNET_ADDRESS_PREFIX \
               aksSubnetName=$AKS_SUBNET_NAME \
               aksSubnetAddressPrefix=$AKS_SUBNET_ADDRESS_PREFIX \
               firewallSubnetAddressPrefix=$FIREWALL_SUBNET_ADDRESS_PREFIX \
               firewallName=$FIREWALL_NAME \
               routeTableName=$ROUTE_TABLE_NAME \
               tags="{\"Environment\":\"$ENVIRONMENT\",\"Project\":\"$PROJECT\",\"ManagedBy\":\"Bicep\",\"Scenario\":\"Egress-Lockdown\"}"
```

---

## Using Parameters Files

Alternatively, you can deploy using the provided `.bicepparam` files:

### Basic Infrastructure

```bash
cd basic
az deployment sub create \
  --location eastus \
  --template-file main.bicep \
  --parameters main.bicepparam
```

### Egress Lockdown

```bash
cd egress-lockdown
az deployment sub create \
  --location eastus \
  --template-file main.bicep \
  --parameters main.bicepparam
```

---

## Deployment Validation

Before deploying to production, validate your templates:

```bash
# For basic infrastructure
cd basic
az deployment sub validate \
  --location eastus \
  --template-file main.bicep \
  --parameters main.bicepparam

# For egress lockdown
cd egress-lockdown
az deployment sub validate \
  --location eastus \
  --template-file main.bicep \
  --parameters main.bicepparam
```

---

## What-If Analysis

Preview changes before deployment:

```bash
# For basic infrastructure
cd basic
az deployment sub what-if \
  --location eastus \
  --template-file main.bicep \
  --parameters main.bicepparam

# For egress lockdown
cd egress-lockdown
az deployment sub what-if \
  --location eastus \
  --template-file main.bicep \
  --parameters main.bicepparam
```

---

## Cost Comparison

| Scenario | Monthly Cost (Est.) | Components |
|----------|---------------------|------------|
| Basic | ~$0 | VNet, Subnet (no charge for VNet/Subnet) |
| Egress Lockdown | ~$912+ | VNet, Subnet, Azure Firewall (~$1.25/hr), Public IP |

> **Note**: Costs are estimates and don't include AKS cluster costs. Actual costs vary by region and usage.

---

## Clean Up

To delete resources from either deployment:

```bash
# Delete basic infrastructure
az group delete --name rg-aks-networking-dev --yes --no-wait

# Delete egress lockdown infrastructure
az group delete --name rg-aks-egress-lockdown-dev --yes --no-wait
```

---

## Prerequisites

- Azure CLI (`az`) version 2.50.0 or later
- Bicep CLI version 0.20.0 or later
- Azure subscription with sufficient permissions to create resources at subscription scope
- Owner or Contributor role on the subscription

### Install Prerequisites

```bash
# Install/Update Azure CLI
# Visit: https://docs.microsoft.com/cli/azure/install-azure-cli

# Install/Update Bicep
az bicep install
az bicep upgrade

# Verify versions
az version
az bicep version

# Login to Azure
az login

# Set subscription (if you have multiple)
az account set --subscription "your-subscription-id"
```

---

## Architecture Patterns

### Basic Infrastructure
```
┌─────────────────────────────────┐
│ Virtual Network (10.0.0.0/16)   │
│                                  │
│  ┌────────────────────────────┐ │
│  │ AKS Subnet (10.0.0.0/24)   │ │
│  │                             │ │
│  │  [AKS Nodes]                │ │
│  └────────────────────────────┘ │
└─────────────────────────────────┘
```

### Egress Lockdown
```
┌──────────────────────────────────────────┐
│ Virtual Network (10.0.0.0/16)            │
│                                           │
│  ┌─────────────────────────────────┐    │
│  │ AKS Subnet (10.0.0.0/24)        │    │
│  │  [AKS Nodes] → UDR: 0.0.0.0/0   │    │
│  └──────────────┬──────────────────┘    │
│                 │                         │
│                 ▼                         │
│  ┌─────────────────────────────────┐    │
│  │ Firewall Subnet (10.0.1.0/26)   │    │
│  │  [Azure Firewall: 10.0.1.4]     │    │
│  └──────────────┬──────────────────┘    │
└─────────────────┼────────────────────────┘
                  ▼
             [Internet]
```

---

## Next Steps

After deploying the infrastructure:

1. **Deploy AKS Cluster**
   ```bash
   # For basic infrastructure
   az aks create \
     --resource-group rg-aks-networking-dev \
     --name aks-cluster-dev \
     --vnet-subnet-id <subnet-id-from-output> \
     --network-plugin azure
   
   # For egress lockdown (requires additional parameters)
   az aks create \
     --resource-group rg-aks-egress-lockdown-dev \
     --name aks-cluster-dev \
     --vnet-subnet-id <subnet-id-from-output> \
     --network-plugin azure \
     --outbound-type userDefinedRouting \
     --api-server-authorized-ip-ranges <your-ip>/32
   ```

2. **Configure kubectl**
   ```bash
   az aks get-credentials \
     --resource-group <resource-group-name> \
     --name aks-cluster-dev
   ```

3. **Verify connectivity**
   ```bash
   kubectl get nodes
   kubectl run test-pod --image=busybox --rm -it -- /bin/sh
   ```

---

## Troubleshooting

### Deployment Fails with "ResourceGroupNotFound"
- Ensure you're deploying at subscription scope (`deployment sub create`)
- The template creates the resource group; don't create it manually first

### Deployment Fails with "InvalidTemplate"
- Validate Bicep syntax: `az bicep build --file main.bicep`
- Check Azure Verified Module versions are current

### Tags Parameter Format Error
- Ensure JSON is properly escaped: `"{\"Key\":\"Value\"}"`
- Or use parameters file instead of inline parameters

### Firewall Deployment Timeout (Egress Lockdown)
- Azure Firewall deployment can take 10-15 minutes
- Use `--no-wait` flag and check status separately if needed

---

## Contributing

When adding new deployment scenarios:

1. Create a new folder under `infra/`
2. Include `main.bicep`, `main.bicepparam`, and `README.md`
3. Use Azure Verified Modules where available
4. Document all parameters and outputs
5. Include deployment commands with environment variables
6. Update this README with the new scenario

---

## Additional Resources

- [Azure Verified Modules](https://aka.ms/avm)
- [AKS Network Concepts](https://learn.microsoft.com/azure/aks/concepts-network)
- [Azure Firewall for AKS](https://learn.microsoft.com/azure/aks/limit-egress-traffic)
- [Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/) 

