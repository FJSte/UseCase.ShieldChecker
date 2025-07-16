@description('Deployment environment.')
param deployEnvironment string

@description('Location for all resources.')
param location string 

@description('Name of the application.')
param appName string

param subnetManagementResourceId string


resource storageAccount 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: 'st${substring(appName,0,min(length(appName),10))}${substring(uniqueString(subscription().subscriptionId),0,4)}${deployEnvironment}001'
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: true
    allowSharedKeyAccess: true
    supportsHttpsTrafficOnly: true
    encryption: {
      requireInfrastructureEncryption: false
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}
resource blobservices 'Microsoft.Storage/storageAccounts/blobServices@2021-04-01' = {
  name: 'default'
  parent: storageAccount
  properties: { containerDeleteRetentionPolicy: { days: 7 }
      }
}

resource dsccontainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: 'windows-powershell-dsc'
  parent: blobservices
  properties: {
    publicAccess: 'Blob'
  }
}
resource execcontainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: 'executor'
  parent: blobservices
  properties: {
    publicAccess: 'Blob'
  }
}
resource genericcontainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  name: 'genericcontent'
  parent: blobservices
  properties: {
    publicAccess: 'Blob'
  }
}

resource storageAccountFun 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: 'st${substring(appName,0,min(length(appName),10))}${substring(uniqueString(subscription().subscriptionId),0,4)}${deployEnvironment}002'
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'

  properties: {
    supportsHttpsTrafficOnly: true
    defaultToOAuthAuthentication: true
    networkAcls: {
      bypass: 'AzureServices'
      virtualNetworkRules: [
        {
          id: subnetManagementResourceId
          action: 'Allow'
          state: 'Succeeded'
        }
      ]
      defaultAction: 'Deny'
    }
  }
}
resource fileservices 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' = {
  name: 'default'
  parent: storageAccountFun
  
}
resource fileService 'Microsoft.Storage/storageAccounts/fileServices/shares@2022-05-01' = {
  parent: fileservices
  name: 'app'
}

output storageAccountDCRName string = storageAccount.name
output storageAccountDCRBlobEndpoint string = storageAccount.properties.primaryEndpoints.blob
output storageAccountFunName string = storageAccountFun.name
output storageAccountFunShareName string = fileService.name




