#Requires -Version 7.0
<# 
.SYNOPSIS
    Update script for ShieldChecker application.

.DESCRIPTION
    This script updates the ShieldChecker web application and DB to the specified environment. If you need to full update leverage the Invoke-Deploy.ps1.

.PARAMETER ResourceGroupName
    Define the name of the resource group. This parameter is mandatory.

.PARAMETER TestDomainFQDN
    Define the fully qualified domain name for the test domain. Default is 'shieldchecker.local'.

.PARAMETER sqlServerDatabaseName
    Define the name of the SQL Server database. This parameter is mandatory.
.PARAMETER sqlServerName
    Define the name of the SQL Server. This parameter is mandatory.

.PARAMETER webAppName
    Define the name of the web application. This parameter is mandatory.

.EXAMPLE
    .\Invoke-UpdateWebAppAndSql.ps1 -TestDomainFQDN "shieldchecker.local" -ResourceGroupName "rg-sc3" -sqlServerName "sql-sbc-uder-westeurope-prd-001.database.windows.net" -sqlServerDatabaseName "sqldb-sbr-prd" -webAppName "app-sbr-uder-westeurope-prd-001"
#>
param(
    [parameter(Mandatory=$true)]
    [string]$sqlServerDatabaseName,

    [parameter(Mandatory=$true)]
    [string]$sqlServerName,

    [parameter(Mandatory=$true)]
    [string]$webAppName,

    [parameter(Mandatory=$true)]
    [string]$ResourceGroupName = "rg-shieldchecker",

    [string]$TestDomainFQDN = 'shieldchecker.local'

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


Write-Host "Check Resource Group" -ForegroundColor Green
if(Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue){
    Write-Host " - Resource Group $ResourceGroupName found"
} else {
    throw "Resource Group $ResourceGroupName not found. Please create the resource group or set the parameter 'CreateRessourceGroupIfNotExists' to $true"
}


Write-Host "SQL Preparation" -ForegroundColor Green
$publicIp = (Invoke-RestMethod -Uri "http://api.ipify.org")
Write-Host " - Create SQL Server Firewall Rule for current Public IP '$publicIp'"
New-AzSqlServerFirewallRule -ResourceGroupName $ResourceGroupName -ServerName $sqlServerName.Replace(".database.windows.net","") -FirewallRuleName "PublicIPOfDeployment" -StartIpAddress $publicIp -EndIpAddress $publicIp | Out-Null
Write-Host " - Wait for 30 seconds to allow the Firewall Rule to be applied"
Start-Sleep -Seconds 30

Write-Host " - Get SQL Server Access Token"
$env:SuppressAzurePowerShellBreakingChangeWarnings = $true
$access_token_sql_SecStr  = (Get-AzAccessToken -ResourceUrl https://database.windows.net -AsSecureString).Token
$access_token_sql = [System.Net.NetworkCredential]::new("", $access_token_sql_SecStr).Password
$env:SuppressAzurePowerShellBreakingChangeWarnings = $false


$CreateDatabase = Get-Content "$PSScriptRoot/step2/SqlScripts/sql-database.sql" -Raw
$InitializeDatabase = Get-Content "$PSScriptRoot/step2/SqlScripts/sql-initialization.sql" -Raw
$InitializeDatabase = $InitializeDatabase -replace "_DomainFQDN_", $TestDomainFQDN
Write-Host " - Create Initial DB"
Invoke-Sqlcmd -ServerInstance $sqlServerName -Database $sqlServerDatabaseName -AccessToken $access_token_sql -query $CreateDatabase
Write-Host " - Initialize DB values"
Invoke-Sqlcmd -ServerInstance $sqlServerName -Database $sqlServerDatabaseName -AccessToken $access_token_sql -query $InitializeDatabase

Write-Host " - Remove SQL Server Firewall Rule for current Public IP '$publicIp'"
Remove-AzSqlServerFirewallRule -ResourceGroupName $ResourceGroupName -ServerName $sqlServerName.Replace(".database.windows.net","") -FirewallRuleName "PublicIPOfDeployment" -Force | Out-Null

Write-Host "Publish Webapp..." -ForegroundColor Green
$webapp = Publish-AzWebApp -ResourceGroupName $ResourceGroupName -Name $webAppName -ArchivePath "$PSScriptRoot/step2/Webapp.zip" -Force
Write-Host " - Webapp published"
Write-Host " - Webapp URL: https://$($webapp.DefaultHostName)"

Write-Host "Update script completed successfully" -ForegroundColor Green
