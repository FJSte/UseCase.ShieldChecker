#Requires -Version 7.0
<# 
.SYNOPSIS
    Deployment script for ShieldChecker application.

.DESCRIPTION
    This script deploys the ShieldChecker application to the specified environment.

.PARAMETER ApplicationName
    Define the name of the application. Default is 'shieldchecker'.

.PARAMETER SQLAdminGroupName
    Define the name of the SQL admin group. This parameter is mandatory.

.PARAMETER DeployEnvironment
    Define the deployment environment. Valid values are 'dev' and 'prd'. Default is 'prd'.

.PARAMETER ResourceGroupName
    Define the name of the resource group. This parameter is mandatory.

.PARAMETER TestDomainFQDN
    Define the fully qualified domain name for the test domain. Default is 'shieldchecker.local'.

.PARAMETER adminUsername
    Define the username for the local admin account which is used on the VMs. Default is 'local_admin'.

.PARAMETER adminPw
    Define the password for the domain and local admin (Windows) and root (Linux) account which is used on the VMs. This parameter is mandatory.

.PARAMETER CreateRessourceGroupIfNotExistsLocation
    Define the location for the resource group if it should be created. If not set, the script will throw an error if the resource group does not exist.

.PARAMETER SleepSeconds
    Define the number of seconds to wait after certain operations, such as creating resources. Default is 60 seconds.
    
.EXAMPLE
    .\Invoke-Deploy.ps1 -SQLAdminGroupName "sg-sql-admin" -ApplicationName "scb" -TestDomainFQDN "shieldchecker.local" -ResourceGroupName "rg-sc3" -adminPw (Read-Host -Prompt "Enter Password" -AsSecureString) -CreateRessourceGroupIfNotExistsLocation 'westeurope''
#>
param(
    [ValidatePattern('^[a-z]+$')] 
    [string]$ApplicationName = 'shieldchecker',

    [parameter(Mandatory=$true)]
    [string]$SQLAdminGroupName,

    [ValidateSet('dev','prd')]
    [string]$DeployEnvironment = 'prd',

    [parameter(Mandatory=$true)]
    [string]$ResourceGroupName = "rg-shieldchecker",

    [string]$TestDomainFQDN = 'shieldchecker.local',

    [string]$adminUsername = "local_admin",

    [Parameter(Mandatory=$true)]
    [SecureString]$adminPw,

    [Alias("CreateRGLocation")]
    [string]$CreateRessourceGroupIfNotExistsLocation,

    [ValidateRange(1, 120)]
    [int]$SleepSeconds = 60
)

# Check if Azure context is available
if (Get-AzContext -ErrorAction SilentlyContinue) {
    Write-Host "Azure Context found" -ForegroundColor Green
} else {
    throw "Azure Context not found. Please authenticate with 'Connect-AzAccount' and select the correct subscription"
}

# Defining important internal variables
Write-Host "Defining internal variables" -ForegroundColor Green
Write-Host "- Script Root Path: $PSScriptRoot"
$reqModules = @("Az.Accounts","Az.Resources","Az.Storage","Az.Websites","Az.Sql","SQLServer")
Write-Host "- Required Modules: $($reqModules -join ", ")"
# Required Permissions
# 'Cloud Application Administrator' and 'Privileged Role Administrator' --> Grant Enterprise Application and Mannaged Identity Permissions
# Entra ID Owner Permissions on RG to grant Permissions to Managed Identities
#Connect-AzAccount -Subscription "bdefc725-6a12-4979-979c-bf039261f5de"

Write-Host "Check Deploy Environment" -ForegroundColor Green
Write-Host "- Check required PowerShell modules"
$reqModules | ForEach-Object {
    if (-not (Get-Module -ListAvailable -Name $_)) {
        Write-Host "  - Installing module $_"
        Install-Module -Name $_ -Force -Scope CurrentUser -AllowClobber
    } else {
        Write-Host "  - Module $_ already installed"
        Import-Module -Name $_
    }
}
try{
    $BicepVersion = bicep --version 
    if($null -ne $BicepVersion){
        Write-Host "  - Bicep Version $BicepVersion found"
    } else {
        Write-Host "  - Bicep Version $BicepVersion found. Please update to 9.0.0 or higher"  
        exit 990001
    }
} catch {
    Write-Host "  - Bicep not found, installing"
    # Create the install folder
    $installPath = "$env:USERPROFILE\.bicep"
    $installDir = New-Item -ItemType Directory -Path $installPath -Force
    $installDir.Attributes += 'Hidden'
    # Fetch the latest Bicep CLI binary
    (New-Object Net.WebClient).DownloadFile("https://github.com/Azure/bicep/releases/latest/download/bicep-win-x64.exe", "$installPath\bicep.exe")
    # Add bicep to your PATH
    $currentPath = (Get-Item -path "HKCU:\Environment" ).GetValue('Path', '', 'DoNotExpandEnvironmentNames')
    if (-not $currentPath.Contains("%USERPROFILE%\.bicep")) { setx PATH ($currentPath + ";%USERPROFILE%\.bicep") }
    if (-not $env:path.Contains($installPath)) { $env:path += ";$installPath" }
    Write-Host "  - Bicep installed"
    # Done!
}


# Check if the SQL Admin group exists and get the ObjectId
Write-Host "Check if the SQL Admin group exists and get the ObjectId" -ForegroundColor Green
$SQLAdminGroup = Get-AzADGroup -DisplayName $SQLAdminGroupName
if($SQLAdminGroup){
    Write-Host " - SQL Admin Group with id $($SQLAdminGroup.Id) exists"
    $SQLAdminGroupObjectId = $SQLAdminGroup.Id
} else {
    throw "SQL Admin Group does not exist, please create and add the user used for the deployment as a member."
}

# Create or get existing Entra ID Enterprise Application for Portal
Write-Host "Create or get existing Entra ID Enterprise Application for Portal" -ForegroundColor Green
$PortalAuthApp = Get-AzADApplication -DisplayName "baseVISION ShieldChecker ($ApplicationName)"
if($PortalAuthApp){ # Check if App already exists
    Write-Host " - App 'baseVISION ShieldChecker ($ApplicationName)' with AppId '$($PortalAuthApp.AppId)' already exists"
} else {
    Write-Host " - App does not exist"
    $PortalAuthApp = New-AzADApplication `
        -DisplayName "baseVISION ShieldChecker ($ApplicationName)" `
        -ReplyUrls "https://$ApplicationName" `
        -AvailableToOtherTenants $false `
        -Web @{ 
            'implicitGrantSettings'=@{
                'enableIdTokenIssuance'=$true; 
                'enableAccessTokenIssuance'=$false; 
            } 
        } `
        -RequiredResourceAccess @(
            @{ResourceAppId="00000003-0000-0000-c000-000000000000"; ResourceAccess=@(
                @{Id="7ab1d382-f21e-4acd-a863-ba3e13f7da61"; Type="Scope"},
                @{Id="14dad69e-099b-42c9-810b-d002981feec1"; Type="Scope"}
                );
            })
    Write-Host " - App 'baseVISION ShieldChecker ($ApplicationName)' with AppId '$($PortalAuthApp.AppId)' created"
    $PortalAuthApp
}

Write-Host "Check Resource Group" -ForegroundColor Green
if(Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue){
    Write-Host " - Resource Group $ResourceGroupName found"
} else {
    if(![String]::IsNullOrWhiteSpace($CreateRessourceGroupIfNotExistsLocation)){
        Write-Host " - Resource Group $ResourceGroupName not found. Creating Resource Group in '$CreateRessourceGroupIfNotExistsLocation'"
        New-AzResourceGroup -Name $ResourceGroupName -Location $CreateRessourceGroupIfNotExistsLocation
    } else {
        throw "Resource Group $ResourceGroupName not found. Please create the resource group or set the parameter 'CreateRessourceGroupIfNotExistsLocation' to a valid azure location."
    }
}

# Initial Infrastructure Deployment
Write-Host "Initial Infrastructure Deployment" -ForegroundColor Green
$outputMain1 = New-AzResourceGroupDeployment `
    -ResourceGroupName $ResourceGroupName `
    -TemplateFile "$PSScriptRoot/step1/main1.bicep" `
    -applicationDatabaseAdminsGroupName $SQLAdminGroupName `
    -applicationDatabaseAdminsObjectId $SQLAdminGroupObjectId `
    -deployEnvironment $DeployEnvironment `
    -adminUsername $adminUsername `
    -adminDcPassword $adminPw `
    -adminWorkerPassword $adminPw `
    -domainFQDN $TestDomainFQDN `
    -appName $ApplicationName `
    -EnterpriseAppTenantDomain $PortalAuthApp.PublisherDomain `
    -EnterpriseAppTenantId (Get-AzContext).Tenant.Id `
    -EnterpriseAppClientId $PortalAuthApp.AppId `
    -sleepSeconds $SleepSeconds `
    -ErrorAction Stop

if($outputMain1){
    Write-Host " - Deployment completed successfully"
} else {
    throw "Deployment failed"
}
    
Write-Host "Publish DSC Item to Storage Account" -ForegroundColor Green    
$st = Get-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $outputMain1.Outputs["storageAccountName"].Value
Write-Host " - Storage Account found: $($st.StorageAccountName)"
If(!(Get-AzStorageContainer -Name "windows-powershell-dsc" -Context $st.Context -ErrorAction SilentlyContinue)){
    Write-Host " - Container 'windows-powershell-dsc' not found. Creating"
    New-AzStorageContainer -Name "windows-powershell-dsc" -Context $st.Context
    Write-Host " - Container 'windows-powershell-dsc' created"
} else {
    Write-Host " - Container 'windows-powershell-dsc' found"
}
$uploadresult = Set-AzStorageBlobContent -Container "windows-powershell-dsc" -File "$PSScriptRoot/step2/VmDsc/DeployDC.ps1.zip" -Blob "DeployDC.ps1.zip" -Context $st.Context -Force

Write-Host " - DSC Configuration uploaded to Storage Account ($($uploadresult.Length) Bytes)"

Write-Host "Publish Executor Binaries to Storage Account" -ForegroundColor Green    
Write-Host " - Storage Account found: $($st.StorageAccountName)"
If(!(Get-AzStorageContainer -Name "executor" -Context $st.Context -ErrorAction SilentlyContinue)){
    Write-Host " - Container 'executor' not found. Creating"
    New-AzStorageContainer -Name "executor" -Context $st.Context
    Write-Host " - Container 'executor' created"
} else {
    Write-Host " - Container 'executor' found"
}
$uploadWinResult = Set-AzStorageBlobContent -Container "executor" -File "$PSScriptRoot/step2/Executor/Windows/ScExecutor.exe" -Blob "WScExecutor.exe" -Context $st.Context -Force
Write-Host " - Windows Executor Console uploaded to Storage Account ($($uploadWinResult.Length) Bytes)"
$uploadLinResult = Set-AzStorageBlobContent -Container "executor" -File "$PSScriptRoot/step2/Executor/Linux/ScExecutor" -Blob "LScExecutor" -Context $st.Context -Force
Write-Host " - Linux Executor Console uploaded to Storage Account ($($uploadLinResult.Length) Bytes)"
'{
  "Logging": {
    "LogLevel": {
      "Default": "Information",
      "Microsoft.Hosting.Lifetime": "Information"
    }
  },
  "AzureFunctionUrl":  "'+$outputMain1.Outputs["functionAppHostname"].Value+'"
}' | Out-File -FilePath "$PSScriptRoot/step2/Executor/appsettings.json" -Force
$uploadAsResult = Set-AzStorageBlobContent -Container "executor" -File "$PSScriptRoot/step2/Executor/appsettings.json" -Blob "appsettings.json" -Context $st.Context -Force
Write-Host " - AppSettings uploaded to Storage Account ($($uploadAsResult.Length) Bytes)"


Write-Host "Publish Generic Content to Storage Account" -ForegroundColor Green    
Write-Host " - Storage Account found: $($st.StorageAccountName)"
If(!(Get-AzStorageContainer -Name "genericcontent" -Context $st.Context -ErrorAction SilentlyContinue)){
    Write-Host " - Container 'genericcontent' not found. Creating"
    New-AzStorageContainer -Name "genericcontent" -Context $st.Context
    Write-Host " - Container 'genericcontent' created"
} else {
    Write-Host " - Container 'genericcontent' found"
}
foreach ($file in Get-ChildItem -Path "$PSScriptRoot/step2/GenericContent/*" -Recurse) {
    $uploadResult = Set-AzStorageBlobContent -Container "genericcontent" -File $file.FullName -Blob $file.Name -Context $st.Context -Force
    Write-Host " - Generic Content '$($file.Name)' uploaded to Storage Account ($($uploadResult.Length) Bytes)"
}

Write-Host "SQL Preparation" -ForegroundColor Green
$publicIp = (Invoke-RestMethod -Uri "http://api.ipify.org")
Write-Host " - Create SQL Server Firewall Rule for current Public IP '$publicIp'"
$SqlSevername = $outputMain1.Outputs["sqlServerName"].Value.Replace(".database.windows.net","")
New-AzSqlServerFirewallRule -ResourceGroupName $ResourceGroupName -ServerName $SqlSevername -FirewallRuleName "PublicIPOfDeployment" -StartIpAddress $publicIp -EndIpAddress $publicIp | Out-Null
Write-Host " - Wait for 30 seconds to allow the Firewall Rule to be applied"
Start-Sleep -Seconds 30

Write-Host " - Get SQL Server Access Token"
$env:SuppressAzurePowerShellBreakingChangeWarnings = $true
$access_token_sql_SecStr  = (Get-AzAccessToken -ResourceUrl https://database.windows.net -AsSecureString).Token
$access_token_sql = [System.Net.NetworkCredential]::new("", $access_token_sql_SecStr).Password
$env:SuppressAzurePowerShellBreakingChangeWarnings = $false

Write-Host " - Adapt permission files"
$InitializeDatabasePermission = Get-Content "$PSScriptRoot/step2/SqlScripts/sql-permissions.sql" -Raw
$InitializeDatabasePermission = $InitializeDatabasePermission -replace "_applicationIdentity_", $outputMain1.Outputs["applicationIdentityName"].Value
$InitializeDatabasePermission = $InitializeDatabasePermission -replace "_vmDcIdentity_", $outputMain1.Outputs["vmDcIdentityName"].Value
$CreateDatabase = Get-Content "$PSScriptRoot/step2/SqlScripts/sql-database.sql" -Raw
$InitializeDatabase = Get-Content "$PSScriptRoot/step2/SqlScripts/sql-initialization.sql" -Raw
$InitializeDatabase = $InitializeDatabase -replace "_DomainFQDN_", $TestDomainFQDN
Write-Host " - Set Permission"
Invoke-Sqlcmd -ServerInstance $outputMain1.Outputs["sqlServerName"].Value -Database $outputMain1.Outputs["sqlServerDatabaseName"].Value -AccessToken $access_token_sql -query $InitializeDatabasePermission
Write-Host " - Create Initial DB"
Invoke-Sqlcmd -ServerInstance $outputMain1.Outputs["sqlServerName"].Value -Database $outputMain1.Outputs["sqlServerDatabaseName"].Value -AccessToken $access_token_sql -query $CreateDatabase
Write-Host " - Initialize DB values"
Invoke-Sqlcmd -ServerInstance $outputMain1.Outputs["sqlServerName"].Value -Database $outputMain1.Outputs["sqlServerDatabaseName"].Value -AccessToken $access_token_sql -query $InitializeDatabase

Write-Host " - Remove SQL Server Firewall Rule for current Public IP '$publicIp'"
Remove-AzSqlServerFirewallRule -ResourceGroupName $ResourceGroupName -ServerName $SqlSevername -FirewallRuleName "PublicIPOfDeployment" -Force | Out-Null


Write-Host "Publish Webapp..." -ForegroundColor Green
$webapp = Publish-AzWebApp -ResourceGroupName $ResourceGroupName -Name $outputMain1.Outputs["webAppName"].Value -ArchivePath "$PSScriptRoot/step2/Webapp.zip" -Force
Write-Host " - Webapp published"
Write-Host " - Webapp URL: https://$($webapp.DefaultHostName)"

Write-Host "Update Enterprise Application Reply URL" -ForegroundColor Green
Update-AzADApplication `
    -ApplicationId $PortalAuthApp.AppId  `
    -ReplyUrl @("https://$($webapp.DefaultHostName)/signin-oidc")  `
    -AvailableToOtherTenants $false `
    -RequiredResourceAccess @(
        @{ResourceAppId="00000003-0000-0000-c000-000000000000"; ResourceAccess=@(
            @{Id="7ab1d382-f21e-4acd-a863-ba3e13f7da61"; Type="Scope"},
            @{Id="14dad69e-099b-42c9-810b-d002981feec1"; Type="Scope"}
            );
        })
Update-AzADApplication `
    -ApplicationId $PortalAuthApp.AppId  `
    -Web @{ 
        'implicitGrantSettings'=@{
            'enableIdTokenIssuance'=$true; 
            'enableAccessTokenIssuance'=$false; 
        } 
    }
Write-Host "Deployment script completed successfully" -ForegroundColor Green
Write-Host "You can now browse to https://$($webapp.DefaultHostName) and start the first run wizard to complete the setup." -ForegroundColor Green
Write-Host "During this wizard the Domain Controller setup is started and you have the possibility to import first tests." -ForegroundColor Green
Write-Host "We also recommend to note the following properties in your documentations as you require them during update process:" -ForegroundColor Green
Write-Host " - Resource Group Name: $ResourceGroupName" 
Write-Host " - Web App Name: $($outputMain1.Outputs["webAppName"].Value)" 
Write-Host " - SQL Server Name: $($outputMain1.Outputs["sqlServer   Name"].Value)" 
Write-Host " - SQL Database Name: $($outputMain1.Outputs["sqlServerDatabaseName"].Value)" 
Write-Host " - SQL Admin Group Name: $SQLAdminGroupName" 
Write-Host " - TestDomainFQDN: $TestDomainFQDN" 
Write-Host " - Application Name: $ApplicationName" 
Write-Host " - Admin Username: $adminUsername" 
Write-Host " - Admin Password: (not shown for security reasons)" 

