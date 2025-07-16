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

param domainFQDN string
param domainControllerName string

param storageAccountDCRName string

param applicationIdentityClientId string
param applicationIdentityId string
param kvUrl string
param kvName string

param subnetManagementResourceId string
param subnetWorkerResourceId string
param subnetDcResourceId string

param sqlServerName string
param sqlServerDatabaseName string

param EnterpriseAppTenantDomain string
param EnterpriseAppTenantId string
param EnterpriseAppClientId string

param storageAccountFunName string
param storageAccountFunShareName string

// The language worker runtime to load in the function app.
var functionWorkerRuntime = 'powershell'


resource appServicePlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: 'asp-${appName}-${location}-${deployEnvironment}-001'
  location: location
  sku: {
    name: 'B2'
  }
}


resource webApp 'Microsoft.Web/sites@2024-04-01' = {
  name: 'app-${appName}-${substring(uniqueString(subscription().subscriptionId),0,4)}-${location}-${deployEnvironment}-001'
  location: location
  dependsOn: [
  ]
  properties: {
    httpsOnly: true
    serverFarmId: appServicePlan.id
    virtualNetworkSubnetId: subnetManagementResourceId
    vnetRouteAllEnabled: true
    siteConfig: {
      appSettings: [
        {
          name: 'AzureSqlDatabase'
          value: 'Server=tcp:${sqlServerName},1433;Initial Catalog=${sqlServerDatabaseName};Authentication=Active Directory Default;Encrypt=True;MultipleActiveResultSets=True;'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'AZURE_TENANT_ID'
          value: tenant().tenantId 
        }
        {
          name: 'AZURE_CLIENT_ID'
          value: applicationIdentityClientId
        }
        {
          name: 'KEYVAULT_URI'
          value: kvUrl
        }
        {
          name: 'AzureAd__Instance'
          value: environment().authentication.loginEndpoint
        }
        {
          name: 'AzureAd__Domain'
          value: EnterpriseAppTenantDomain
        }
        {
          name: 'AzureAd__TenantId'
          value: EnterpriseAppTenantId
        }
        {
          name: 'AzureAd__ClientId'
          value: EnterpriseAppClientId
        }
        {
          name: 'AzureAd__CallbackPath'
          value: '/signin-oidc'
        }
        {
          name: 'MicrosoftGraph__BaseUrl'
          value: 'https://graph.microsoft.com'
        }
        {
          name: 'MicrosoftGraph__Version'
          value: 'v1.0'
        }
        {
          name: 'MicrosoftGraph__Scopes__0'
          value: 'user.read'
        }
        {
          name: 'SC_FUN_HOSTNAME'
          value: functionApp.properties.defaultHostName
        }
        {
          name: 'SC_FUN_KEY'
          value: listKeys('${functionApp.id}/host/default', '2019-08-01').functionKeys.default
        }
      ]
      netFrameworkVersion: 'v9.0'
      minTlsVersion: '1.2'
      linuxFxVersion: null
    }
  }

  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${applicationIdentityId}': {}
    }
  }
}

resource storageAccountFun 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountFunName
}

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: 'fun-${appName}-${substring(uniqueString(subscription().subscriptionId),0,4)}-${location}-${deployEnvironment}-001'
  location: location
  kind: 'functionapp'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${applicationIdentityId}': {}
    }
  }
  properties: {
    httpsOnly: true
    serverFarmId: appServicePlan.id
    virtualNetworkSubnetId: subnetManagementResourceId
    vnetRouteAllEnabled: true
    vnetContentShareEnabled: true
    siteConfig: {
      alwaysOn: true
      powerShellVersion: '7.4'
      appSettings: [
        {
          name: 'SC_AZURE_SQL_DATABASE_NAME'
          value: sqlServerDatabaseName
        }
        {
          name: 'SC_AZURE_SQL_SERVER_NAME'
          value: sqlServerName
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: appInsights.properties.InstrumentationKey
        }
        {
          name: 'AZURE_CLIENT_ID'
          value: applicationIdentityClientId 
        }
        {
          name: 'AZURE_TENANT_ID '
          value: tenant().tenantId
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountFunName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccountFun.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountFunName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccountFun.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: storageAccountFunShareName
        }
        {
          name: 'WEBSITE_CONTENTOVERVNET'
          value: '1'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: functionWorkerRuntime
        }
        {
          name: 'KEYVAULT_URI'
          value: kvUrl
        }
        {
          name: 'KEYVAULT_NAME'
          value: kvName
        }
        {
          name: 'SC_DEPLOY_ENVIRONMENT'
          value: deployEnvironment
        }
        {
          name: 'SC_AZ_LOCATION'
          value: location
        }
        {
          name: 'SC_APP_NAME'
          value: appName
        }
        {
          name: 'SC_AZ_RESSOURCEGROUP_NAME'
          value: resourceGroup().name
        }
        {
          name: 'SC_AZ_WORKER_SUBNET_ID'
          value: subnetWorkerResourceId
        }
        {
          name: 'SC_AZ_DC_SUBNET_ID'
          value: subnetDcResourceId
        }
        {
          name: 'SC_DOMAIN_FQDN'
          value: domainFQDN
        }
        {
          name: 'SC_DOMAIN_CONTROLLER_NAME'
          value: domainControllerName
        } 
        {
          name: 'SC_STORAGE_DC_DSC'
          value: storageAccountDCRName
        }
      ]
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
    }
  }
}

resource deploymentScript 'Microsoft.Resources/deploymentScripts@2023-08-01' = {
  name: 'inlinePSFun'
  location: location
  kind: 'AzurePowerShell'
  properties: {
    azPowerShellVersion: '10.0'
    scriptContent: '''
      Start-Sleep -Seconds 60
    '''
    retentionInterval:  'PT1H'
  }
}

resource scheduler 'Microsoft.Web/sites/functions@2022-03-01' = {
  parent: functionApp
  name: 'JobProcessorWorker'
  dependsOn: [
    deploymentScript
  ]
  properties: {
    files: {
      'run.ps1' : loadTextContent('./FunctionApp/JobProcessorWorker/run.ps1')
      'function.json' : loadTextContent('./FunctionApp/JobProcessorWorker/function.json')
      '../requirements.psd1' : loadTextContent('./FunctionApp/requirements.psd1')
      '../profile.ps1' : loadTextContent('./FunctionApp/profile.ps1')
      '../host.json' : loadTextContent('./FunctionApp/host.json')
    }
  }
}
resource schedulerDC 'Microsoft.Web/sites/functions@2022-03-01' = {
  parent: functionApp
  name: 'JobProcessorDC'
  dependsOn: [
    deploymentScript
  ]
  properties: {
    files: {
      'run.ps1' : loadTextContent('./FunctionApp/JobProcessorDC/run.ps1')
      'function.json' : loadTextContent('./FunctionApp/JobProcessorDC/function.json')
    }
  }
}
resource scripts 'Microsoft.Web/sites/functions@2022-03-01' = {
  parent: functionApp
  name: 'Scripts'
  dependsOn: [
    deploymentScript
  ]
  properties: {
    files: {
      'run.ps1' : loadTextContent('./FunctionApp/Scripts/run.ps1')
      'function.json' : loadTextContent('./FunctionApp/Scripts/function.json')
    }
  }
}
resource importTests 'Microsoft.Web/sites/functions@2022-03-01' = {
  parent: functionApp
  name: 'ImportTests'
  dependsOn: [
    deploymentScript
  ]
  properties: {
    files: {
      'run.ps1' : loadTextContent('./FunctionApp/ImportTests/run.ps1')
      'function.json' : loadTextContent('./FunctionApp/ImportTests/function.json')
    }
  }
}

resource provisioningDC 'Microsoft.Web/sites/functions@2022-03-01' = {
  parent: functionApp
  name: 'ProvisioningDC'
  dependsOn: [
    deploymentScript
  ]
  properties: {
    files: {
      'run.ps1' : loadTextContent('./FunctionApp/ProvisioningDC/run.ps1')
      'function.json' : loadTextContent('./FunctionApp/ProvisioningDC/function.json')
    }
  }
}

resource job 'Microsoft.Web/sites/functions@2022-03-01' = {
  parent: functionApp
  name: 'Job'
  dependsOn: [
    deploymentScript
  ]
  properties: {
    files: {
      'run.ps1' : loadTextContent('./FunctionApp/Job/run.ps1')
      'function.json' : loadTextContent('./FunctionApp/Job/function.json')
    }
  }
}

resource jobUpdater 'Microsoft.Web/sites/functions@2022-03-01' = {
  parent: functionApp
  name: 'JobUpdater'
  dependsOn: [
    deploymentScript
  ]
  properties: {
    files: {
      'run.ps1' : loadTextContent('./FunctionApp/JobUpdater/run.ps1')
      'function.json' : loadTextContent('./FunctionApp/JobUpdater/function.json')
    }
  }
}
  
  resource autoScheduler 'Microsoft.Web/sites/functions@2022-03-01' = {
  parent: functionApp
  name: 'AutoScheduler'
  dependsOn: [
    deploymentScript
  ]
  properties: {
    files: {
      'run.ps1' : loadTextContent('./FunctionApp/AutoScheduler/run.ps1')
      'function.json' : loadTextContent('./FunctionApp/AutoScheduler/function.json')
    }
  }
}

resource workspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: 'log-${appName}-${location}-${deployEnvironment}-001'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    workspaceCapping: {}
  }
}
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${appName}-${location}-${deployEnvironment}-001'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Flow_Type: 'Bluefield'
    WorkspaceResourceId: workspace.id
    RetentionInDays: 30
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

resource appServiceAppSettings 'Microsoft.Web/sites/config@2020-06-01' = {
  parent: webApp
  name: 'logs'
  properties: {
    applicationLogs: {
      fileSystem: {
        level: 'Warning'
      }
    }
    httpLogs: {
      fileSystem: {
        retentionInMb: 40
        enabled: true
      }
    }
    failedRequestsTracing: {
      enabled: true
    }
    detailedErrorMessages: {
      enabled: true
    }
  }
}

resource DiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'LogAnalytics'
  scope: appServicePlan
  properties: {
    metrics: [
      {
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
        category: 'AllMetrics'
      }
    ]
    workspaceId: workspace.id
    logAnalyticsDestinationType: null
  }
}
resource DiagnosticSettingsWeb 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'LogAnalyticsWeb'
  scope: webApp
  properties: {
    metrics: [
      {
        enabled: true
        retentionPolicy: {
          days: 0
          enabled: false
        }
        category: 'AllMetrics'
      }
    ]
    workspaceId: workspace.id
    logAnalyticsDestinationType: null
  }
}

output webAppName string = webApp.name
output functionAppHostname string = functionApp.properties.defaultHostName
