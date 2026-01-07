using './main.bicep'

// Resource Group parameters
param resourceGroupName = 'rg-aks-egress-lockdown-dev'
param location = 'eastus'

// Virtual Network parameters
param vnetName = 'vnet-aks-egress-dev'
param vnetAddressPrefix = '10.0.0.0/16'

// AKS Subnet parameters
param aksSubnetName = 'aks-subnet'
param aksSubnetAddressPrefix = '10.0.0.0/24'

// Azure Firewall Subnet parameters
param firewallSubnetAddressPrefix = '10.0.1.0/26'

// Azure Firewall parameters
param firewallName = 'afw-aks-dev'

// Route Table parameters
param routeTableName = 'rt-aks-egress-dev'

// Jump Server parameters
param jumpServerSubnetName = 'jump-server-subnet'
param jumpServerSubnetAddressPrefix = '10.0.2.0/27'
param jumpServerName = 'vm-jump-server'
param jumpServerAdminUsername = 'azureuser'
param jumpServerSshPublicKey = '' // Must be provided at deployment time
param jumpServerVmSize = 'Standard_B2s'

// Tags
param tags = {
  Environment: 'Dev'
  Project: 'AKS-Networking'
  ManagedBy: 'Bicep'
  Scenario: 'Egress-Lockdown'
}
