# Define a parameter named $Timer, typically used for a timer-based trigger in PowerShell automation
param($Timer)
# Output the current date and time to the console, indicating when the script is run
Write-Output "AutoScheduler Timer trigger function executed at: $(Get-Date)"


#region Functions

enum DomainControllerStatus
{
    NotStarted
    VMRequested
    DcProvisioningRequested
    Initialized
    ResetRequested
    Error
}


function Update-JobStatus {
    param(
        [DomainControllerStatus]$Status,
        [Parameter(Mandatory=$false)]
        [string]$SchedulerLog,
        [Parameter(Mandatory=$false)]
        [string]$access_token_sql
    )
    
    Invoke-Sqlcmd `
        -ServerInstance $Settings["SC_AZURE_SQL_SERVER_NAME"] `
        -Database $Settings["SC_AZURE_SQL_DATABASE_NAME"] `
        -AccessToken $access_token_sql `
        -query "Update 
                    [dbo].[SystemStatus] 
                SET 
                    [DomainControllerStatus] = $([int]$Status),
                    [DomainControllerLog] = '$($SchedulerLog.Replace("'", "''"))'
                WHERE 
                    [ID] = 1"
}
#endregion Functions

#region load settings
$Settings = @{}
$Settings.Add("AZURE_CLIENT_ID", $env:AZURE_CLIENT_ID)
$Settings.Add("KEYVAULT_NAME", $env:KEYVAULT_NAME)
$Settings.Add("AZURE_TENANT_ID", $env:AZURE_TENANT_ID)
$Settings.Add("SC_AZURE_SQL_DATABASE_NAME", $env:SC_AZURE_SQL_DATABASE_NAME)
$Settings.Add("SC_AZURE_SQL_SERVER_NAME", $env:SC_AZURE_SQL_SERVER_NAME)
$Settings.Add("SC_AZ_LOCATION", $env:SC_AZ_LOCATION)
$Settings.Add("SC_APP_NAME", $env:SC_APP_NAME)
$Settings.Add("SC_AZ_RESSOURCEGROUP_NAME", $env:SC_AZ_RESSOURCEGROUP_NAME)
$Settings.Add("SC_AZ_WORKER_SUBNET_ID", $env:SC_AZ_WORKER_SUBNET_ID)
$Settings.Add("WEBSITE_HOSTNAME", $env:WEBSITE_HOSTNAME)
$Settings.Add("SC_DOMAIN_FQDN", $env:SC_DOMAIN_FQDN)
$Settings.Add("SC_DEPLOY_ENVIRONMENT", $env:SC_DEPLOY_ENVIRONMENT)
$Settings.Add("SC_STORAGE_DC_DSC", $env:SC_STORAGE_DC_DSC)
$Settings.Add("SC_AZ_DC_SUBNET_ID", $env:SC_AZ_DC_SUBNET_ID)




Connect-AzAccount -Identity -AccountId $Settings["AZURE_CLIENT_ID"]
$access_token_sql_SecStr  = (Get-AzAccessToken -ResourceUrl https://database.windows.net -AsSecureString).Token
$access_token_sql = [System.Net.NetworkCredential]::new("", $access_token_sql_SecStr).Password

Write-Host "Load SystemStatus from SQL Server"
$SystemStatusDb = Invoke-Sqlcmd `
                    -ServerInstance $Settings["SC_AZURE_SQL_SERVER_NAME"] `
                    -Database $Settings["SC_AZURE_SQL_DATABASE_NAME"] `
                    -AccessToken $access_token_sql `
                    -query 'SELECT *
                            FROM [dbo].[SystemStatus] WHERE [ID] = 1'

if($SystemStatusDb.FirstRunWizard -eq 1){
    Write-Host "First Run Wizard is not yet completed, skip processing jobs"
    exit 
}

Write-Host "Load Settings from SQL Server"
$SettingsDb = Invoke-Sqlcmd `
                    -ServerInstance $Settings["SC_AZURE_SQL_SERVER_NAME"] `
                    -Database $Settings["SC_AZURE_SQL_DATABASE_NAME"] `
                    -AccessToken $access_token_sql `
                    -query 'SELECT TOP (1) *
                            FROM [dbo].[Settings]'


$SettingsDb | Get-Member -MemberType *Property | ForEach-Object {
    if($_.name -ne "Item"){
        $Settings.Add($_.name,$SettingsDb.($_.name)) 
    }
} 

Write-Host "Load KeyVault Secrets"Load active Jobs from SQL Ser
$Settings.Add("AdminUsername", (Get-AzKeyVaultSecret -VaultName $Settings["KEYVAULT_NAME"] -Name "AdminUsername" -AsPlainText))
$Settings.Add("AdminDcPassword", (Get-AzKeyVaultSecret -VaultName $Settings["KEYVAULT_NAME"] -Name "AdminDcPassword").SecretValue)
$Settings.Add("AdminWorkerPassword", (Get-AzKeyVaultSecret -VaultName $Settings["KEYVAULT_NAME"] -Name "AdminWorkerPassword").SecretValue)

$Settings.GetEnumerator() | ForEach-Object {
    Write-Host "Setting: $($_.Key) = $("$($_.Value)".SubString(0, [System.Math]::Min(128, "$($_.Value)".Length)))" 
}
#endregion load settings


#region generating jobs
Write-Host "Load AutoSchedule Entries"
$AutoScheduleEntries = Invoke-Sqlcmd `
    -ServerInstance $Settings["SC_AZURE_SQL_SERVER_NAME"] `
    -Database $Settings["SC_AZURE_SQL_DATABASE_NAME"] `
    -AccessToken $access_token_sql `
    -query 'SELECT * FROM [dbo].[AutoSchedule] WHERE [Enabled] = 1 AND [NextExecution] <= GETDATE()'
if($AutoScheduleEntries.Count -eq 0){
    Write-Host "No AutoSchedule entries found, exiting"
    exit
}
foreach($AutoScheduleEntry in $AutoScheduleEntries){
    Write-Host "Processing AutoSchedule Entry: $($AutoScheduleEntry.Name)"
    try {
        # Get Matching TestDefinitions

        if($AutoScheduleEntry.FilterOperatingSystem){
            $OSFilter = "'" + $AutoScheduleEntry.FilterOperatingSystem + "'"
        } else {
            $OSFilter = 'NULL'
        }
        # Limit the number of TestDefinitions to 1000
        if($AutoScheduleEntry.FilterRandomCount -gt 0){
            $MaxTestDefinitions = $AutoScheduleEntry.FilterRandomCount
        } else {
            $MaxTestDefinitions = 1000
        }
        $Query =    'DECLARE @AutoScheduleId INT = '+ $AutoScheduleEntry.ID+';
                    DECLARE @FilterOperatingSystem INT =' + $OSFilter + ';
                    DECLARE @FilterExecution INT = '+ $AutoScheduleEntry.FilterExecution + ';

                    SELECT TOP ('+$MaxTestDefinitions+') * FROM TestDefinition AS t 
                    WHERE
                    (
                    t.ID IN (SELECT TestDefinitionsID FROM [dbo].[AutoScheduleTestDefinition] WHERE AutoSchedulesID = @AutoScheduleId) 
                    OR 
                    @AutoScheduleId IS NULL
                    OR
                    (SELECT COUNT(*) FROM [dbo].[AutoScheduleTestDefinition] WHERE AutoSchedulesID = @AutoScheduleId) = 0
                    ) 
                    AND
                    (
                    t.ID NOT IN (SELECT UseCaseID FROM [dbo].[TestJob] WHERE [Status] BETWEEN 0 AND 3) 
                    )
                    AND 
                    (
                    @FilterOperatingSystem is NULL
                    OR
                    @FilterOperatingSystem = t.[OperatingSystem]
                    )
                    AND 
                    (
                    @FilterExecution is NULL
                    OR 
                    t.ID NOT IN (
                    SELECT UseCaseID FROM TestJob 
                        WHERE 
                            Created > CASE 
                                WHEN @FilterExecution IN (1,3) THEN DATEADD(week,-1,GETDATE())
                                WHEN @FilterExecution IN (2,4) THEN DATEADD(month,-1,GETDATE())
                                WHEN @FilterExecution IN (0) THEN GETDATE()
                            END 
                            AND 
                            CASE 
                                WHEN @FilterExecution IN (1,2) AND Result IN (0,1) THEN 1
                                WHEN @FilterExecution IN (1,2) AND Result NOT IN (0,1) THEN 0
                                WHEN @FilterExecution IN (0,3,4) THEN 1
                            END = 1
                        )
                    )
                    '
        $TestDefinitions = Invoke-Sqlcmd `
            -ServerInstance $Settings["SC_AZURE_SQL_SERVER_NAME"] `
            -Database $Settings["SC_AZURE_SQL_DATABASE_NAME"] `
            -AccessToken $access_token_sql `
            -query $Query

        # Check if there are any TestDefinitions to process
        if($TestDefinitions.Count -eq 0){
            Write-Host "No TestDefinitions found for AutoSchedule Entry: $($AutoScheduleEntry.Name), skipping"
            continue
        }
        Write-Host "Found $($TestDefinitions.Count) TestDefinitions for AutoSchedule Entry: $($AutoScheduleEntry.Name)"
        # Create a new TestJob for each TestDefinition
        $TestDefinitions | ForEach-Object {
            $TestDefinition = $_
            Write-Host "Creating TestJob for TestDefinition: $($TestDefinition.Name)"
            # Insert the new TestJob into the database
            Invoke-Sqlcmd `
                -ServerInstance $Settings["SC_AZURE_SQL_SERVER_NAME"] `
                -Database $Settings["SC_AZURE_SQL_DATABASE_NAME"] `
                -AccessToken $access_token_sql `
                -query "INSERT INTO [dbo].[TestJob] ([Created],[Modified], [UseCaseID], [Status],[Result]) 
                        VALUES (GETDATE(),GETDATE(), $($TestDefinition.ID), 0, 3);"
            
            Write-Host "Updated NextExecution for AutoSchedule Entry: $($AutoScheduleEntry.Name)"
            # Update the NextExecution time for the AutoSchedule Entry
            switch ($AutoScheduleEntry.AutoScheduleType) {
                
                0 {
                    # Weekly
                    $NextExecution = (Get-Date).AddDays(7)
                }
                1 {
                    # Monthly
                    $NextExecution = (Get-Date).AddMonths(1)
                }
                2 {
                    # Quarterly
                    $NextExecution = (Get-Date).AddMonths(3)
                }
                3 {
                    # Quarterly
                    $NextExecution = (Get-Date).AddDays(1)
                }
                default {
                    Write-Error "Unknown AutoScheduleType: $($AutoScheduleEntry.AutoScheduleType), Using Monthly as default"
                    $NextExecution = (Get-Date).AddMonths(1)
                }
            }
            
            Invoke-Sqlcmd `
                -ServerInstance $Settings["SC_AZURE_SQL_SERVER_NAME"] `
                -Database $Settings["SC_AZURE_SQL_DATABASE_NAME"] `
                -AccessToken $access_token_sql `
                -query "UPDATE [dbo].[AutoSchedule] SET [NextExecution] = '$($NextExecution.ToString("yyyy-MM-dd HH:mm:ss"))' WHERE [ID] = $($AutoScheduleEntry.ID);"
            
            Write-Host "NextExecution for AutoSchedule Entry: $($AutoScheduleEntry.Name) updated to $($NextExecution.ToString("yyyy-MM-dd HH:mm:ss"))"
        }

    } catch {
        Write-Error "Error processing AutoSchedule Entry: $($AutoScheduleEntry.Name) - $_"
        
    }
}


#end region generating jobs
