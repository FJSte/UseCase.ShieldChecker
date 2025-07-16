
@description('Display Name of the database administrators group from Entra ID. The user running this wizard needs to be in this group.')
param applicationDatabaseAdminsGroupName string

@description('Object ID of the database administrators group from Entra ID. The user running this wizard needs to be in this group.')
param applicationDatabaseAdminsObjectId string 


@allowed([
  'dev'
  'prd'
])
param deployEnvironment string = 'dev'

@description('Location for all resources.')
param location string = resourceGroup().location

param appName string

param adminUsername string
@secure()
param adminDcPassword string
@secure()
param adminWorkerPassword string

param domainControllerName string = 'dc01'
param domainFQDN string
param sleepSeconds int = 60

param EnterpriseAppTenantDomain string = 'kurcontoso.onmicrosoft.com'
param EnterpriseAppTenantId string = tenant().tenantId
param EnterpriseAppClientId string

@description('Deployment module of network')
module deployment_network 'resource.network.bicep' = {
  name: 'module.network'
  params: {
    deployEnvironment: deployEnvironment
    location: location
    appName: appName
    domainControllerName: domainControllerName
  }
}
@description('Deployment module of identity for app id')
module deployment_identity_app 'resource.identity.app.bicep' = {
  name: 'module.identity.app'
  params: {
    deployEnvironment: deployEnvironment
    location: location
    appName: appName
    sleepSeconds: sleepSeconds
  }
}
@description('Deployment module of identity for db id')
module deployment_identity_db 'resource.identity.db.bicep' = {
  name: 'module.identity.db'
  params: {
    deployEnvironment: deployEnvironment
    location: location
    appName: appName
    sleepSeconds: sleepSeconds
  }
}
@description('Deployment module of identity for vmdc id')
module deployment_identity_vmdc 'resource.identity.vmdc.bicep' = {
  name: 'module.identity.vmdc'
  params: {
    deployEnvironment: deployEnvironment
    location: location
    appName: appName
  }
}

@description('Deployment module of storage account')
module deployment_storage 'resource.storage.bicep' = {
  name: 'module.storage'
  params: {
    deployEnvironment: deployEnvironment
    location: location
    appName: appName
    subnetManagementResourceId: deployment_network.outputs.subnetManagementResourceId
  }
}

@description('Deployment module of key vault')
module deployment_kv 'resource.kv.bicep' = {
  name: 'module.kv'
  params: {
    deployEnvironment: deployEnvironment
    location: location
    applicationIdentityPrincipalId: deployment_identity_app.outputs.applicationIdentityPrincipalId
    adminDcPassword: adminDcPassword
    adminWorkerPassword: adminWorkerPassword
    adminUsername: adminUsername
    appName: appName
  }
}

@description('Deployment module of web components')
module deployment_web 'resource.web.bicep' = {
  name: 'module.web'
  params: {
    deployEnvironment: deployEnvironment
    location: location
    appName: appName
    subnetManagementResourceId: deployment_network.outputs.subnetManagementResourceId
    subnetWorkerResourceId: deployment_network.outputs.subnetWorkerResourceId
    subnetDcResourceId: deployment_network.outputs.subnetDcResourceId
    sqlServerDatabaseName: deployment_sql.outputs.sqlServerDatabaseName
    sqlServerName: deployment_sql.outputs.sqlServerName
    applicationIdentityClientId: deployment_identity_app.outputs.applicationIdentityClientId
    applicationIdentityId: deployment_identity_app.outputs.applicationIdentityId
    kvUrl: deployment_kv.outputs.kvUrl
    kvName: deployment_kv.outputs.kvName
    EnterpriseAppClientId: EnterpriseAppClientId
    EnterpriseAppTenantDomain: EnterpriseAppTenantDomain
    EnterpriseAppTenantId: EnterpriseAppTenantId
    domainFQDN: domainFQDN
    domainControllerName: domainControllerName
    storageAccountDCRName: deployment_storage.outputs.storageAccountDCRName
    storageAccountFunName: deployment_storage.outputs.storageAccountFunName
    storageAccountFunShareName: deployment_storage.outputs.storageAccountFunShareName
  }
}

@description('Deployment module of azure sql')
module deployment_sql 'resource.sql.bicep' = {
  name: 'module.sql'
  params: {
    applicationDatabaseAdminsGroupName: applicationDatabaseAdminsGroupName
    applicationDatabaseAdminsObjectId: applicationDatabaseAdminsObjectId
    deployEnvironment: deployEnvironment
    location: location
    appName: appName
    subnetManagementResourceId: deployment_network.outputs.subnetManagementResourceId
    dbIdentityId: deployment_identity_db.outputs.dbIdentityId
    kvName: deployment_kv.outputs.kvName
  }
}



output sqlServerName string = deployment_sql.outputs.sqlServerName
output sqlServerDatabaseName string = deployment_sql.outputs.sqlServerDatabaseName
output subnetWorkerNetworkResourceId string = deployment_network.outputs.subnetWorkerResourceId
output subnetManagementNetworkResourceId string = deployment_network.outputs.subnetManagementResourceId
output subnetDcNetworkResourceId string = deployment_network.outputs.subnetDcResourceId
output storageAccountName string = deployment_storage.outputs.storageAccountDCRName
output sqlConnectionString string = deployment_sql.outputs.sqlConnectionString
output applicationIdentityName string = deployment_identity_app.outputs.applicationIdentityName
output vmDcIdentityName string = deployment_identity_vmdc.outputs.vmDcIdentityName
output webAppName string = deployment_web.outputs.webAppName
output functionAppHostname string = deployment_web.outputs.functionAppHostname
