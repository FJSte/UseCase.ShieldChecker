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

param sleepSeconds int = 60

var appMdeAppRoles = [
  'Machine.ReadWrite.All'
  'Machine.Offboard'
]
var appGraphAppRoles = [
  'SecurityAlert.ReadWrite.All'
]

///////////////////////////
//
// Initialize Graph Providers
//
///////////////////////////

// Initialize the Graph provider
extension 'br:mcr.microsoft.com/bicep/extensions/microsoftgraph/v1.0:0.1.8-preview'

// Get the Resource Id of the Graph resource in the tenant
resource graphSpn 'Microsoft.Graph/servicePrincipals@v1.0' existing =  {
  appId: '00000003-0000-0000-c000-000000000000'
}
// Get the Resource Id of the Security Graph resource in the tenant
resource graphMdeSpn 'Microsoft.Graph/servicePrincipals@v1.0' existing =  {
  appId: 'fc780465-2017-40d4-a0c5-307022471b92'
}

///////////////////////////
//
// Create Identity
//
///////////////////////////

resource applicationIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' = {
  name: 'id-${appName}app-${deployEnvironment}-${location}-001'
  location: location
}

resource deploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'inlinePSApp'
  location: location
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '10.0'
    arguments: ' -clientId ${applicationIdentity.properties.clientId} -sleepSeconds ${sleepSeconds}'
    scriptContent: '''
      param([string] $clientId, [int] $sleepSeconds)
      Write-Output "The argument is {0}." -f $clientId
      Write-Output "The sleep seconds is {0}." -f $sleepSeconds
      Start-Sleep -Seconds $sleepSeconds
      $DeploymentScriptOutputs = @{}
      $DeploymentScriptOutputs['clientid'] = $clientId
    '''
    retentionInterval:  'PT1H'
  }
}

// Get the Principal Id of the Managed Identity resource
resource miAppSpn 'Microsoft.Graph/servicePrincipals@v1.0' existing =  {
  
  appId: deploymentScript.properties.outputs.clientid
}



///////////////////////////
//
// Azure Permissions
//
///////////////////////////

//Grants the application the VM creatin permsission "Virtual Machine Contributor"
var roleAssignmentName= guid('id-${appName}app-${deployEnvironment}-${location}-001','9980e02c-c2be-4d73-94e8-173b1dc7cf3c', resourceGroup().id)
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: roleAssignmentName
  dependsOn: [
    deploymentScript
  ]
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '9980e02c-c2be-4d73-94e8-173b1dc7cf3c')
    principalId: applicationIdentity.properties.principalId
  }
}
//Grants the application the VM creatin permsission "Network Contributor"
var roleAssignmentNameNet= guid('id-${appName}app-${deployEnvironment}-${location}-001','4d97b98b-1d4f-4787-a291-c67834d212e7', resourceGroup().id)
resource roleAssignmentNet 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: roleAssignmentNameNet
  dependsOn: [
    deploymentScript
  ]
  properties: {
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '4d97b98b-1d4f-4787-a291-c67834d212e7')
    principalId: applicationIdentity.properties.principalId
  }
}


///////////////////////////
//
// Microsoft Security Graph Scopes
//
///////////////////////////

// Looping through the Mde App Roles and assigning them to the Managed Identity
resource assignAppAppRole 'Microsoft.Graph/appRoleAssignedTo@v1.0' = [for appRole in appMdeAppRoles:  {
  appRoleId: (filter(graphMdeSpn.appRoles, role => role.value == appRole)[0]).id
  principalId: miAppSpn.id
  resourceId: graphMdeSpn.id
}]

///////////////////////////
//
// Microsoft Graph Scopes 
//
///////////////////////////

// Looping through the Graph App Roles and assigning them to the Managed Identity
resource assignGraphAppAppRole 'Microsoft.Graph/appRoleAssignedTo@v1.0' = [for appRole in appGraphAppRoles:  {
  appRoleId: (filter(graphSpn.appRoles, role => role.value == appRole)[0]).id
  principalId: miAppSpn.id
  resourceId: graphSpn.id
}]




// Output variables
output applicationIdentityName string = applicationIdentity.name
output applicationIdentityPrincipalId string = applicationIdentity.properties.principalId
output applicationIdentityClientId string = applicationIdentity.properties.clientId
output applicationIdentityId string = applicationIdentity.id
