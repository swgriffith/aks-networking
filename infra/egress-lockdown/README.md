# AKS Infrastructure with Egress Lockdown

This deployment creates a secure AKS infrastructure with egress traffic lockdown using Azure Firewall and an Ubuntu jump server for secure access:
- Resource Group
- Virtual Network
- AKS Subnet with User Defined Route (UDR)
- Azure Firewall Subnet
- Azure Firewall with basic allow rules for AKS
- Route Table with default route (0.0.0.0/0) pointing to Azure Firewall
- Ubuntu Jump Server with public IP for SSH access

## Architecture

All internet-bound traffic from the AKS subnet is forced through Azure Firewall via a User Defined Route (UDR). This provides centralized control and visibility over egress traffic. The jump server provides secure SSH access to manage resources.

```
┌────────────────────────────────────────────────────────────┐
│ Virtual Network (10.0.0.0/16)                              │
│                                                             │
│  ┌────────────────────────────┐                            │
│  │ AKS Subnet (10.0.0.0/24)   │                            │
│  │                             │                            │
│  │ ┌────────┐  ┌────────┐     │                            │
│  │ │ Node 1 │  │ Node 2 │     │                            │
│  │ └───┬────┘  └───┬────┘     │                            │
│  └──────┼──────────┼──────────┘                            │
│         │          │                                        │
│         │  UDR: 0.0.0.0/0 → 10.0.1.4                       │
│         │          │                                        │
│         ▼          ▼                                        │
│  ┌──────────────────────────────┐                          │
│  │ Azure Firewall Subnet        │                          │
│  │ (10.0.1.0/26)                │                          │
│  │                               │                          │
│  │   ┌──────────────────┐       │                          │
│  │   │ Azure Firewall   │       │                          │
│  │   │ (10.0.1.4)       │       │                          │
│  │   └────────┬─────────┘       │                          │
│  └────────────┼──────────────────┘                          │
│               │                                             │
│  ┌──────────────────────────────┐                          │
│  │ Jump Server Subnet           │                          │
│  │ (10.0.2.0/27)                │                          │
│  │                               │                          │
│  │   ┌──────────────────┐       │                          │
│  │   │ Ubuntu Jump      │◄──────┼────── SSH (TCP/22)      │
│  │   │ Server           │       │                          │
│  │   └──────────────────┘       │                          │
│  └──────────────────────────────┘                          │
│                                                             │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
                     Internet
```

## Resources Created

- **Resource Group**: Container for all AKS-related resources
- **Virtual Network**: Network isolation with three subnets
- **AKS Subnet**: Dedicated subnet for AKS node pools with route table applied
- **Azure Firewall Subnet**: Required subnet for Azure Firewall
- **Jump Server Subnet**: Dedicated subnet for jump server with NSG
- **Azure Firewall**: Provides egress filtering and control
- **Route Table**: Forces all internet traffic (0.0.0.0/0) through the firewall
- **Network Security Group**: Controls SSH access to jump server
- **Ubuntu Jump Server**: Ubuntu 22.04 LTS VM with public IP for SSH access

## Prerequisites

- Azure CLI installed
- Bicep CLI installed
- Azure subscription with appropriate permissions

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `resourceGroupName` | string | `rg-aks-egress-lockdown-dev` | Name of the resource group |
| `location` | string | `eastus` | Azure region for resources |
| `vnetName` | string | `vnet-aks-egress-dev` | Name of the virtual network |
| `vnetAddressPrefix` | string | `10.0.0.0/16` | Address space for the VNet |
| `aksSubnetName` | string | `aks-subnet` | Name of the AKS subnet |
| `aksSubnetAddressPrefix` | string | `10.0.0.0/24` | Address prefix for AKS subnet |
| `firewallSubnetAddressPrefix` | string | `10.0.1.0/26` | Address prefix for Firewall subnet |
| `firewallName` | string | `afw-aks-dev` | Name of the Azure Firewall |
| `routeTableName` | string | `rt-aks-egress-dev` | Name of the route table |
| `jumpServerSubnetName` | string | `jump-server-subnet` | Name of the jump server subnet |
| `jumpServerSubnetAddressPrefix` | string | `10.0.2.0/27` | Address prefix for jump server subnet |
| `jumpServerName` | string | `vm-jump-server` | Name of the jump server VM |
| `jumpServerAdminUsername` | string | `azureuser` | Admin username for jump server |
| `jumpServerSshPublicKey` | string | **Required** | SSH public key for jump server authentication |
| `jumpServerVmSize` | string | `Standard_B2s` | VM size for jump server |
| `tags` | object | See main.bicepparam | Tags to apply to resources |

## Deployment

### Generate SSH Key for Jump Server

If you don't already have an SSH key, generate one:

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/aks-jump-server -C "aks-jump-server"
```

### Using Azure CLI with parameters file

Update the `main.bicepparam` file with your SSH public key, then deploy:

```bash
az deployment sub create \
  --location eastus \
  --template-file main.bicep \
  --parameters main.bicepparam \
               jumpServerSshPublicKey="$(cat ~/.ssh/aks-jump-server.pub)"
```

### Using Azure CLI with environment variables

First, set the environment variables:

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
export JUMP_SERVER_NAME="vm-jump-server"
export JUMP_SERVER_ADMIN_USERNAME="azureuser"
export JUMP_SERVER_SSH_KEY="$(cat ~/.ssh/aks-jump-server.pub)"
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
               firewallSubnetAddressPrefix=$FIREWALL_SUBNET_ADDRESS_PREFIX \
               firewallName=$FIREWALL_NAME \
               routeTableName=$ROUTE_TABLE_NAME \
               jumpServerName=$JUMP_SERVER_NAME \
               jumpServerAdminUsername=$JUMP_SERVER_ADMIN_USERNAME \
               jumpServerSshPublicKey="$JUMP_SERVER_SSH_KEY" \
               tags="{\"Environment\":\"$ENVIRONMENT\",\"Project\":\"$PROJECT\",\"ManagedBy\":\"Bicep\",\"Scenario\":\"Egress-Lockdown\"}"
```

### Using Azure CLI with inline parameters (without environment variables)

```bash
az deployment sub create \
  --location eastus \
  --template-file main.bicep \
  --parameters resourceGroupName=rg-aks-egress-demo \
               location=eastus \
               vnetName=vnet-aks-egress-demo \
               vnetAddressPrefix=10.0.0.0/16 \
               aksSubnetName=aks-subnet \
               aksSubnetAddressPrefix=10.0.0.0/24 \
               firewallSubnetAddressPrefix=10.0.1.0/26 \
               firewallName=afw-aks-demo \
               routeTableName=rt-aks-egress-demo \
               jumpServerName=vm-jump-server \
               jumpServerAdminUsername=azureuser \
               jumpServerSshPublicKey="$(cat ~/.ssh/aks-jump-server.pub)"
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
| `firewallId` | string | Resource ID of the Azure Firewall |
| `firewallName` | string | Name of the Azure Firewall |
| `firewallPrivateIp` | string | Private IP address of the Azure Firewall |
| `routeTableId` | string | Resource ID of the route table |
| `routeTableName` | string | Name of the route table |
| `jumpServerId` | string | Resource ID of the jump server |
| `jumpServerName` | string | Name of the jump server |

## Connecting to the Jump Server

After deployment, connect to the jump server using SSH:

```bash
# Get the public IP address
JUMP_IP=$(az vm list-ip-addresses \
  --resource-group rg-aks-egress-lockdown-dev \
  --name vm-jump-server \
  --query "[0].virtualMachine.network.publicIpAddresses[0].ipAddress" \
  -o tsv)

# Connect via SSH
ssh -i ~/.ssh/aks-jump-server azureuser@$JUMP_IP
```

From the jump server, you can:
- Access AKS cluster nodes (if configured)
- Manage Azure resources using Azure CLI
- Run kubectl commands against the AKS cluster
- Troubleshoot network connectivity issues

## Firewall Rules

The deployment includes basic firewall rules required for AKS:

### Network Rules
- **NTP**: UDP/123 for time synchronization
- **DNS**: UDP/53 for DNS resolution
- **HTTPS**: TCP/443 for general HTTPS traffic

### Application Rules
- **AKS Required FQDNs**:
  - `*.hcp.<region>.azmk8s.io` - AKS control plane
  - `mcr.microsoft.com` - Microsoft Container Registry
  - `*.data.mcr.microsoft.com` - MCR data endpoints
  - `management.azure.com` - Azure Resource Manager
  - `login.microsoftonline.com` - Azure AD authentication
  - `packages.microsoft.com` - Microsoft packages
  - `acs-mirror.azureedge.net` - AKS mirror

> **Note**: You may need to add additional rules based on your workload requirements.

## Cost Considerations

Azure Firewall is a premium service with hourly charges plus data processing fees. Consider:
- **Azure Firewall**: Runs 24/7 with hourly costs (~$1.25/hour or ~$912/month) plus data processing
- **Jump Server (Standard_B2s)**: ~$30-40/month (can be stopped when not in use)
- Data processing charges apply to all firewall traffic

For dev/test environments, consider:
- Azure Firewall Basic SKU (lower cost)
- Stop/deallocate the jump server when not in use
- Firewall policies to control rules
- Using B-series burstable VMs for jump server (good for intermittent use)

## Security Best Practices

1. **Principle of Least Privilege**: The included rules are basic. Review and restrict to only what your AKS cluster needs.
2. **Jump Server Access**: 
   - Restrict SSH access to specific IP addresses in the NSG
   - Use Azure Bastion instead of public IP for production
   - Regularly update the jump server OS and packages
   - Enable Azure AD authentication for SSH
3. **Enable Diagnostic Logs**: Send firewall logs to Log Analytics for monitoring
4. **Regular Rule Reviews**: Audit firewall rules periodically
5. **Use Firewall Policy**: Consider migrating to Azure Firewall Policy for centralized management
6. **Key Management**: Store SSH private keys securely (Azure Key Vault, not in repos)

## Next Steps

After deploying this infrastructure, you can:
1. Connect to the jump server and install Azure CLI and kubectl
2. Deploy an AKS cluster into the created subnet with `--outbound-type userDefinedRouting`
3. Configure jump server to access AKS cluster nodes
4. Add additional firewall rules for your specific workload requirements
5. Configure diagnostic settings for the firewall
6. Set up Azure Monitor for firewall metrics and logs
7. Implement Azure Firewall Policy for advanced rule management
8. Consider replacing the jump server public IP with Azure Bastion for production

## Troubleshooting

### AKS nodes unable to communicate
- Verify firewall rules allow required AKS FQDNs
- Check route table is properly associated with AKS subnet
- Confirm firewall private IP is 10.0.1.4

### Firewall rules not working
- Ensure network rules have priority lower than application rules
- Verify source addresses match AKS subnet CIDR
- Check firewall logs for denied traffic

### Cannot connect to jump server via SSH
- Verify NSG allows SSH from your IP address
- Check that the jump server is running (not stopped/deallocated)
- Confirm you're using the correct SSH private key
- Test connectivity: `nc -zv <jump-server-ip> 22`

### Jump server cannot reach internet
- Jump server subnet is not associated with the route table by default
- This allows direct internet access for management
- If you need egress control, associate the route table with the jump server subnet

## Clean Up

To delete all resources:

```bash
az group delete --name rg-aks-egress-lockdown-dev --yes --no-wait
```

> **Note**: Firewall deletion can take 10-15 minutes.
