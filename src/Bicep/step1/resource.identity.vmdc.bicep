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



///////////////////////////
//
// Create Identity
//
///////////////////////////

resource vmDcIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-07-31-preview' = {
  name: 'id-${appName}vmdc-${deployEnvironment}-${location}-001'
  location: location
}



// Output variables
output vmDcIdentityName string = vmDcIdentity.name
output vmDcIdentityId string = vmDcIdentity.id
