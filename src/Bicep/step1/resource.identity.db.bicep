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

// Define permissions required for the identities
var dbGraphAppRoles = [
  'User.Read.All'
  'GroupMember.Read.All'
  'Application.Read.All'
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



///////////////////////////
//
// Create Identity
//
///////////////////////////


resource dbIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' = {
  name: 'id-${appName}db-${deployEnvironment}-${location}-001'
  location: location
}



resource deploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'inlinePSDb'
  location: location
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '10.0'
    arguments: ' -clientId ${dbIdentity.properties.clientId} -sleepSeconds ${sleepSeconds}'
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
resource miSpn 'Microsoft.Graph/servicePrincipals@v1.0' existing =  {
  appId: deploymentScript.properties.outputs.clientid
}

///////////////////////////
//
// Microsoft Graph Scopes 
//
///////////////////////////

// Looping through the Graph App Roles and assigning them to the Managed Identity
resource assignAppRole 'Microsoft.Graph/appRoleAssignedTo@v1.0' = [for appRole in dbGraphAppRoles:  {
  appRoleId: (filter(graphSpn.appRoles, role => role.value == appRole)[0]).id
  principalId: miSpn.id
  resourceId: graphSpn.id
}]


// Output variables
output dbIdentityId string = dbIdentity.id
