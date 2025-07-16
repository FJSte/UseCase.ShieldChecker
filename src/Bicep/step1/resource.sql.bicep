@description('Display Name of the database administrators group or user.')
param applicationDatabaseAdminsGroupName string = 'sg-sql-admin'

@description('Object ID of the database administrators group.')
param applicationDatabaseAdminsObjectId string = '33e728a4-d032-443c-96d4-5bebb65c089d'

@allowed([
  'dev'
  'prd'
])
@description('Deployment environment.')
param deployEnvironment string = 'dev'

@description('Location for all resources.')
param location string 

@description('Name of the application.')
param appName string

param subnetManagementResourceId string

param dbIdentityId string

param kvName string

resource sqlServer 'Microsoft.Sql/servers@2023-08-01-preview' = {
  name: 'sql-${appName}-${substring(uniqueString(subscription().subscriptionId),0,4)}-${location}-${deployEnvironment}-001'
  location: location
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${dbIdentityId}': {}
    }
  }
  properties: {
    administrators: {
      azureADOnlyAuthentication: true
      administratorType: 'ActiveDirectory'
      sid: applicationDatabaseAdminsObjectId
      login: applicationDatabaseAdminsGroupName
    }
    primaryUserAssignedIdentityId: dbIdentityId
    minimalTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  
  }

  resource sqlServerDatabase 'databases' = {
    name: 'sqldb-${appName}-${deployEnvironment}'
    location: location
    sku: {
      name: 'Basic'
      tier: 'Basic'
    }
  }
}
resource sqlServerNetwork 'Microsoft.Sql/servers/virtualNetworkRules@2023-05-01-preview' = {
  name: 'subnetManagement'
  parent: sqlServer
  properties: {
    ignoreMissingVnetServiceEndpoint: false
    virtualNetworkSubnetId: subnetManagementResourceId
  }
}
resource allowAccessToAzureServices 'Microsoft.Sql/servers/firewallRules@2020-11-01-preview' = {
  name: 'AllowAllWindowsAzureIps'
  parent: sqlServer
  properties: {
    startIpAddress: '0.0.0.0'
    endIpAddress: '0.0.0.0'
  }
}
resource kv 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: kvName
} 
resource kvSqlConnectionString 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: kv
  name: 'SqlConnectionString'
  properties: {
    value: 'Server=tcp:${sqlServerName},1433;Initial Catalog=${sqlServer::sqlServerDatabase.name};Authentication=Active Directory Default;Encrypt=True;MultipleActiveResultSets=True;'
  }
}

var sqlServerName = '${sqlServer.name}${environment().suffixes.sqlServerHostname}'
output sqlServerName string = sqlServerName
output sqlServerDatabaseName string = sqlServer::sqlServerDatabase.name
output sqlConnectionString string = 'Server=tcp:${sqlServerName},1433;Initial Catalog=${sqlServer::sqlServerDatabase.name};Authentication=Active Directory Default;Encrypt=True;MultipleActiveResultSets=True;'
