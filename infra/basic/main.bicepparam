using './main.bicep'

// Resource Group parameters
param resourceGroupName = 'rg-aks-networking-dev'
param location = 'eastus'

// Virtual Network parameters
param vnetName = 'vnet-aks-dev'
param vnetAddressPrefix = '10.0.0.0/16'

// AKS Subnet parameters
param aksSubnetName = 'aks-subnet'
param aksSubnetAddressPrefix = '10.0.0.0/24'

// Tags
param tags = {
  Environment: 'Dev'
  Project: 'AKS-Networking'
  ManagedBy: 'Bicep'
}
