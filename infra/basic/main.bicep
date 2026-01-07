targetScope = 'subscription'

@description('The name of the resource group')
param resourceGroupName string

@description('The location for all resources')
param location string

@description('The name of the virtual network')
param vnetName string

@description('The address prefix for the virtual network')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('The name of the AKS subnet')
param aksSubnetName string = 'aks-subnet'

@description('The address prefix for the AKS subnet')
param aksSubnetAddressPrefix string = '10.0.0.0/24'

@description('Tags to apply to all resources')
param tags object = {
  Environment: 'Dev'
  Project: 'AKS-Networking'
}

// Deploy Resource Group
module resourceGroup 'br/public:avm/res/resources/resource-group:0.4.0' = {
  name: 'rg-deployment'
  params: {
    name: resourceGroupName
    location: location
    tags: tags
  }
}

// Deploy Virtual Network with AKS subnet
module virtualNetwork 'br/public:avm/res/network/virtual-network:0.5.2' = {
  name: 'vnet-deployment'
  scope: az.resourceGroup(resourceGroupName)
  params: {
    name: vnetName
    location: location
    addressPrefixes: [
      vnetAddressPrefix
    ]
    subnets: [
      {
        name: aksSubnetName
        addressPrefix: aksSubnetAddressPrefix
      }
    ]
    tags: tags
  }
  dependsOn: [
    resourceGroup
  ]
}

@description('The resource ID of the resource group')
output resourceGroupId string = resourceGroup.outputs.resourceId

@description('The name of the resource group')
output resourceGroupName string = resourceGroup.outputs.name

@description('The resource ID of the virtual network')
output vnetId string = virtualNetwork.outputs.resourceId

@description('The name of the virtual network')
output vnetName string = virtualNetwork.outputs.name

@description('The resource ID of the AKS subnet')
output aksSubnetId string = virtualNetwork.outputs.subnetResourceIds[0]

@description('The name of the AKS subnet')
output aksSubnetName string = virtualNetwork.outputs.subnetNames[0]
