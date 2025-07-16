# Deployment

## Requirements to run the Installation

* Install the latest version of Azure PowerShell, including the Bicep CLI.
* Dedicated test Tenant
* Single Microsoft Defender XDR License like E5/A5.
* Azure Subscription
* PowerShell Core 7+
* Azure CLI
* Bicep CLI

## Preparation

### Create DB Admin Group in Entra ID

1. Create a security group in Entra ID.
2. Add your user account to this group. If using DevOps, add the Service Principal of the pipeline instead.
3. Note the Object ID and the name of the group for later use.

## Deployment Steps

### Prerequisite: Log in to Azure PowerShell

Before running any deployment scripts, ensure you are logged into Azure PowerShell and have selected the correct subscription:

```powershell
Connect-AzAccount
Select-AzSubscription -SubscriptionId "<YourSubscriptionId>"
```

### Initial Deployment and Updates

1. Ensure the DB Admin group is created as described in the preparation steps.
2. Run the following PowerShell script to perform the initial deployment. Replace the placeholders with the appropriate values for your environment. You will be asked for the Admin Password automatically as soon you execute the comand. :

```powershell
./Invoke-Deploy.ps1 -SQLAdminGroupName "<SQLAdminGroupName>" `
                    -ApplicationName "<ApplicationName>" `
                    -TestDomainFQDN "<TestDomainFQDN>" `
                    -ResourceGroupName "<ResourceGroupName>" `
                    -adminPw (Read-Host -Prompt "Enter Password" -AsSecureString) `
                    -CreateRessourceGroupIfNotExistsLocation "<Location>"
```

This script will deploy all required resources, including the web application and database. Note done all used parameters so you can update it in the future to a newer version without issues. When the script finished you can browse to the newly created webpage ans start the first run wizard to complete the setup. During this wizard the Domain Controller setup is started and you have the possibility to import first tests.


### Updating an Existing Deployment 
If there is a new version with changes only to the web application and database, run the following PowerShell script instead to speed up the deployment. If you are unsure, then just use the initial used command 'Invoke-Deploy.ps1'. Replace the placeholders with the appropriate values for your environment:

```powershell
./Invoke-UpdateWebAppAndSql.ps1 -ResourceGroupName "<ResourceGroupName>" `
                                -sqlServerName "<SQLServerName>" `
                                -sqlServerDatabaseName "<SQLServerDatabaseName>" `
                                -webAppName "<WebAppName>" `
                                -TestDomainFQDN "<TestDomainFQDN>"
```

This will update the web application and database without redeploying other resources.

