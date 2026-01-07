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

@description('The address prefix for the Azure Firewall subnet')
param firewallSubnetAddressPrefix string = '10.0.1.0/26'

@description('The name of the Azure Firewall')
param firewallName string

@description('The name of the route table')
param routeTableName string

@description('The name of the jump server subnet')
param jumpServerSubnetName string = 'jump-server-subnet'

@description('The address prefix for the jump server subnet')
param jumpServerSubnetAddressPrefix string = '10.0.2.0/27'

@description('The name of the jump server VM')
param jumpServerName string

@description('The admin username for the jump server')
param jumpServerAdminUsername string = 'azureuser'

@description('The SSH public key for the jump server')
@secure()
param jumpServerSshPublicKey string

@description('The VM size for the jump server')
param jumpServerVmSize string = 'Standard_B2s'

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

// Deploy Network Security Group for Jump Server
module jumpServerNsg 'br/public:avm/res/network/network-security-group:0.5.0' = {
  name: 'nsg-jump-server-deployment'
  scope: az.resourceGroup(resourceGroupName)
  params: {
    name: 'nsg-${jumpServerName}'
    location: location
    securityRules: [
      {
        name: 'allow-ssh-inbound'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          description: 'Allow SSH inbound from anywhere'
        }
      }
    ]
    tags: tags
  }
  dependsOn: [
    resourceGroup
  ]
}

// Deploy Route Table with default route to firewall
module routeTable 'br/public:avm/res/network/route-table:0.5.0' = {
  name: 'rt-deployment'
  scope: az.resourceGroup(resourceGroupName)
  params: {
    name: routeTableName
    location: location
    routes: [
      {
        name: 'default-to-firewall'
        properties: {
          addressPrefix: '0.0.0.0/0'
          nextHopType: 'VirtualAppliance'
          nextHopIpAddress: '10.0.1.4' // Azure Firewall's private IP
        }
      }
    ]
    tags: tags
  }
  dependsOn: [
    resourceGroup
  ]
}

// Deploy Virtual Network with AKS subnet and Azure Firewall subnet
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
        routeTableResourceId: routeTable.outputs.resourceId
      }
      {
        name: 'AzureFirewallSubnet'
        addressPrefix: firewallSubnetAddressPrefix
      }
      {
        name: jumpServerSubnetName
        addressPrefix: jumpServerSubnetAddressPrefix
        networkSecurityGroupResourceId: jumpServerNsg.outputs.resourceId
      }
    ]
    tags: tags
  }
  dependsOn: [
    resourceGroup
    routeTable
  ]
}

// Deploy Azure Firewall
module firewall 'br/public:avm/res/network/azure-firewall:0.5.0' = {
  name: 'firewall-deployment'
  scope: az.resourceGroup(resourceGroupName)
  params: {
    name: firewallName
    location: location
    virtualNetworkResourceId: virtualNetwork.outputs.resourceId
    publicIPAddressObject: {
      name: '${firewallName}-pip'
      publicIPAllocationMethod: 'Static'
      skuName: 'Standard'
      skuTier: 'Regional'
    }
    networkRuleCollections: [
      {
        name: 'allow-aks-outbound'
        properties: {
          priority: 100
          action: {
            type: 'Allow'
          }
          rules: [
            {
              name: 'allow-ntp'
              description: 'Allow NTP for time synchronization'
              protocols: [
                'UDP'
              ]
              sourceAddresses: [
                aksSubnetAddressPrefix
                jumpServerSubnetAddressPrefix
              ]
              destinationAddresses: [
                '*'
              ]
              destinationPorts: [
                '123'
              ]
            }
            {
              name: 'allow-dns'
              description: 'Allow DNS resolution'
              protocols: [
                'UDP'
              ]
              sourceAddresses: [
                aksSubnetAddressPrefix
                jumpServerSubnetAddressPrefix
              ]
              destinationAddresses: [
                '*'
              ]
              destinationPorts: [
                '53'
              ]
            }
            {
              name: 'allow-https'
              description: 'Allow HTTPS for package downloads and API access'
              protocols: [
                'TCP'
              ]
              sourceAddresses: [
                aksSubnetAddressPrefix
                jumpServerSubnetAddressPrefix
              ]
              destinationAddresses: [
                '*'
              ]
              destinationPorts: [
                '443'
              ]
            }
            {
              name: 'allow-http'
              description: 'Allow HTTP for package repository access'
              protocols: [
                'TCP'
              ]
              sourceAddresses: [
                jumpServerSubnetAddressPrefix
              ]
              destinationAddresses: [
                '*'
              ]
              destinationPorts: [
                '80'
              ]
            }
          ]
        }
      }
    ]
    applicationRuleCollections: [
      {
        name: 'allow-aks-fqdns'
        properties: {
          priority: 200
          action: {
            type: 'Allow'
          }
          rules: [
            {
              name: 'allow-aks-required'
              description: 'Allow required AKS FQDNs'
              protocols: [
                {
                  protocolType: 'Https'
                  port: 443
                }
              ]
              sourceAddresses: [
                aksSubnetAddressPrefix
              ]
              targetFqdns: [
                '*.hcp.${location}.azmk8s.io'
                'mcr.microsoft.com'
                '*.data.mcr.microsoft.com'
                'management.azure.com'
                'login.microsoftonline.com'
                'packages.microsoft.com'
                'acs-mirror.azureedge.net'
              ]
            }
            {
              name: 'allow-jump-server-tools'
              description: 'Allow jump server to download kubectl, helm, and Azure CLI'
              protocols: [
                {
                  protocolType: 'Https'
                  port: 443
                }
                {
                  protocolType: 'Http'
                  port: 80
                }
              ]
              sourceAddresses: [
                jumpServerSubnetAddressPrefix
              ]
              targetFqdns: [
                'pkgs.k8s.io'
                '*.pkgs.k8s.io'
                'baltocdn.com'
                '*.baltocdn.com'
                'get.helm.sh'
                'aka.ms'
                'packages.microsoft.com'
                'azure.archive.ubuntu.com'
                'archive.ubuntu.com'
                'security.ubuntu.com'
                'ports.ubuntu.com'
                '*.ubuntu.com'
                'download.docker.com'
              ]
            }
          ]
        }
      }
    ]
    tags: tags
  }
  dependsOn: [
    virtualNetwork
  ]
}

// Deploy Ubuntu Jump Server
module jumpServer 'br/public:avm/res/compute/virtual-machine:0.9.0' = {
  name: 'jump-server-deployment'
  scope: az.resourceGroup(resourceGroupName)
  params: {
    name: jumpServerName
    location: location
    osType: 'Linux'
    vmSize: jumpServerVmSize
    zone: 0
    adminUsername: jumpServerAdminUsername
    disablePasswordAuthentication: true
    encryptionAtHost: false
    managedIdentities: {
      systemAssigned: true
    }
    publicKeys: [
      {
        path: '/home/${jumpServerAdminUsername}/.ssh/authorized_keys'
        keyData: jumpServerSshPublicKey
      }
    ]
    customData: base64('''
#cloud-config
package_update: true
package_upgrade: true

packages:
  - apt-transport-https
  - ca-certificates
  - curl
  - gnupg
  - lsb-release

runcmd:
  # Install kubectl
  - curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  - chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg
  - echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
  - chmod 644 /etc/apt/sources.list.d/kubernetes.list
  - apt-get update
  - apt-get install -y kubectl
  
  # Install Helm
  - curl https://baltocdn.com/helm/signing.asc | gpg --dearmor -o /usr/share/keyrings/helm.gpg
  - echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | tee /etc/apt/sources.list.d/helm-stable-debian.list
  - apt-get update
  - apt-get install -y helm
  
  # Install Azure CLI
  - curl -sL https://aka.ms/InstallAzureCLIDeb | bash
  
  # Configure kubectl bash completion
  - kubectl completion bash > /etc/bash_completion.d/kubectl
  - helm completion bash > /etc/bash_completion.d/helm

final_message: "Jump server setup complete with kubectl, curl, helm, and Azure CLI installed"
''')
    imageReference: {
      publisher: 'Canonical'
      offer: '0001-com-ubuntu-server-jammy'
      sku: '22_04-lts-gen2'
      version: 'latest'
    }
    osDisk: {
      createOption: 'FromImage'
      diskSizeGB: 30
      managedDisk: {
        storageAccountType: 'Premium_LRS'
      }
      caching: 'ReadWrite'
    }
    nicConfigurations: [
      {
        nicSuffix: '-nic'
        enableAcceleratedNetworking: false
        ipConfigurations: [
          {
            name: 'ipconfig1'
            subnetResourceId: virtualNetwork.outputs.subnetResourceIds[2] // Jump server subnet
            pipConfiguration: {
              publicIpNameSuffix: '-pip'
              publicIPAllocationMethod: 'Static'
              skuName: 'Standard'
              zone: 0
            }
          }
        ]
      }
    ]
    tags: tags
  }
  dependsOn: [
    virtualNetwork
    jumpServerNsg
  ]
}

// Assign Contributor role to jump server on the resource group
module jumpServerRoleAssignment 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  name: 'jump-server-role-assignment'
  scope: az.resourceGroup(resourceGroupName)
  params: {
    principalId: jumpServer.outputs.systemAssignedMIPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor
    resourceId: resourceGroup.outputs.resourceId
  }
  dependsOn: [
    jumpServer
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

@description('The resource ID of the Azure Firewall')
output firewallId string = firewall.outputs.resourceId

@description('The name of the Azure Firewall')
output firewallName string = firewall.outputs.name

@description('The private IP of the Azure Firewall')
output firewallPrivateIp string = firewall.outputs.privateIp

@description('The resource ID of the route table')
output routeTableId string = routeTable.outputs.resourceId

@description('The name of the route table')
output routeTableName string = routeTable.outputs.name

@description('The resource ID of the jump server')
output jumpServerId string = jumpServer.outputs.resourceId

@description('The name of the jump server')
output jumpServerName string = jumpServer.outputs.name

@description('The system-assigned managed identity principal ID of the jump server')
output jumpServerPrincipalId string = jumpServer.outputs.systemAssignedMIPrincipalId
