
@description('Deployment environment.')
param deployEnvironment string

@description('Location for all resources.')
param location string 

@description('Name of the application.')
param appName string

param domainControllerName string

resource vnet 'Microsoft.Network/virtualNetworks@2021-02-01' = {
  name: 'vnet-${appName}-${location}-${deployEnvironment}-001'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: 'Management'
        properties: {
          addressPrefix: '10.0.1.0/24'
          serviceEndpoints: [
            {
              service: 'Microsoft.Sql'
            }
            {
              service: 'Microsoft.Web'
            }
            {
              service: 'Microsoft.Storage'
            }
          ]
          natGateway: {
            id: natgateway.id
          }
          delegations: [
            {
              name: 'Microsoft.Web/serverFarms'
              properties: {
                serviceName: 'Microsoft.Web/serverFarms'
              }
            }
          ]
          privateEndpointNetworkPolicies: 'Enabled'
          privateLinkServiceNetworkPolicies: 'Enabled'
        }
      }
      {
        name: 'Worker'
        properties: {
          addressPrefix: '10.0.2.0/24'
          natGateway: {
            id: natgateway.id
          }
        }
      }
      {
        name: 'DomainController'
        properties: {
          addressPrefix: '10.0.3.0/24'
          natGateway: {
            id: natgateway.id
          }
        }
      }
    ]
  }
}

resource subnetManagement 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' existing = {
  parent: vnet
  name: 'Management'
}

resource subnetWorker 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' existing = {
  parent: vnet
  name: 'Worker'
}
resource subnetDc 'Microsoft.Network/virtualNetworks/subnets@2024-01-01' existing = {
  parent: vnet
  name: 'DomainController'
}

resource natgateway 'Microsoft.Network/natGateways@2021-05-01' = {
  name: 'ng-${appName}-${location}-${deployEnvironment}-001'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    idleTimeoutInMinutes: 4
    publicIpAddresses: [
      {
        id: publicnatip.id
      }
    ]
  }
}
resource publicnatip 'Microsoft.Network/publicIPAddresses@2021-05-01' = {
  name: 'pip-${appName}-${location}-${deployEnvironment}-001'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAddressVersion: 'IPv4'
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
  }
}

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2022-11-01' = {
  name: 'nsg-${appName}-${deployEnvironment}-001'
  location: location
  properties: {
    flushConnection: false
    securityRules: [
      {
        name: 'AllowMyIpAddressRDPInbound'
        type: 'Microsoft.Network/networkSecurityGroups/securityRules'
        properties: {
          protocol: 'TCP'
          sourcePortRange: '*'
          destinationPortRange: '3389'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
          sourcePortRanges: []
          destinationPortRanges: []
          sourceAddressPrefixes: []
          destinationAddressPrefixes: []
        }
      }
    ]
  }
}
// Create the virtual machine's NIC and associate it with the applicable public IP address and subnet
resource nic 'Microsoft.Network/networkInterfaces@2021-05-01' = {
  name: 'nic-${domainControllerName}-01-${appName}-${deployEnvironment}-001'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddressVersion: 'IPv4'
          privateIPAddress: '10.0.3.10'
          subnet: {
            id: subnetDc.id
          }
        }
      }
    ]
  }
}


output subnetManagementResourceId string = subnetManagement.id
output subnetWorkerResourceId string = subnetWorker.id
output subnetDcResourceId string = subnetDc.id
