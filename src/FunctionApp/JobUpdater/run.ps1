param($Request, $TriggerMetadata)



#region load settings
$Settings = @{}
$Settings.Add("AZURE_CLIENT_ID", $env:AZURE_CLIENT_ID)
$Settings.Add("KEYVAULT_NAME", $env:KEYVAULT_NAME)
$Settings.Add("AZURE_TENANT_ID", $env:AZURE_TENANT_ID)
$Settings.Add("SC_AZURE_SQL_DATABASE_NAME", $env:SC_AZURE_SQL_DATABASE_NAME)
$Settings.Add("SC_AZURE_SQL_SERVER_NAME", $env:SC_AZURE_SQL_SERVER_NAME)
$Settings.Add("SC_AZ_LOCATION", $env:SC_AZ_LOCATION)
$Settings.Add("SC_AZ_RESSOURCEGROUP_NAME", $env:SC_AZ_RESSOURCEGROUP_NAME)
$Settings.Add("SC_DOMAIN_FQDN", $env:SC_DOMAIN_FQDN)
$Settings.Add("SC_AZ_WORKER_SUBNET_ID", $env:SC_AZ_WORKER_SUBNET_ID)
$Settings.Add("WEBSITE_HOSTNAME", $env:WEBSITE_HOSTNAME)
$Settings.Add("SC_DEPLOY_ENVIRONMENT", $env:SC_DEPLOY_ENVIRONMENT)
$Settings.Add("SC_STORAGE_DC_DSC", $env:SC_STORAGE_DC_DSC)
$Settings.Add("SC_AZ_DC_SUBNET_ID", $env:SC_AZ_DC_SUBNET_ID)
$Settings.Add("MAXCHAR", 1048576)


[string]$workername = [string]($Request.Query.workername)
Write-Information "Workername: $workername"
Write-Information "Request Body: $($Request.Body | ConvertTo-Json -Depth 10)"
[int]$status = [int]($Request.Body.status)
Write-Information "Status: $status"
[string]$TestOutput = [string]($Request.Body.testOutput)
Write-Information "TestOutput: $TestOutput"
if($TestOutput.Length -gt $Settings["MAXCHAR"]){
    $TestOutput = $TestOutput.subString(($TestOutput.Length - $Settings["MAXCHAR"]), $TestOutput.Length)
}
[string]$ExecutorOutput = [string]($Request.Body.executorOutput)
Write-Information "ExecutorOutput: $ExecutorOutput"
if($ExecutorOutput.Length -gt $Settings["MAXCHAR"]){
    $ExecutorOutput = $ExecutorOutput.subString(($ExecutorOutput.Length - $Settings["MAXCHAR"]), $ExecutorOutput.Length)
}

if(-not $workername -or [String]::IsNullOrEmpty($workername)) {
    Write-Error "Invalid workername"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::BadRequest
        Body = "Invalid workername or no workername specified"
    })
} elseif(-not $status -or $status -notin @(2,7)) {
    Write-Error "Invalid status"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::BadRequest
        Body = "Invalid status or no status specified"
    })
} elseif((-not $TestOutput -or [String]::IsNullOrEmpty($TestOutput)) -and (-not $ExecutorOutput -or [String]::IsNullOrEmpty($ExecutorOutput))) {
    Write-Error "Invalid TestOutput/Executor Output"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::BadRequest
        Body = "Invalid TestOutput/Executor Output or no TestOutput/Executor Output specified"
    })
}  else {
    Write-Host "Connecting to Azure with Managed Identity"
    Connect-AzAccount -Identity -AccountId $Settings["AZURE_CLIENT_ID"]
    Write-Host "Connected to Azure"

    Write-Host "Retrieving access token for SQL Server"     
    $access_tokenSecStr  = (Get-AzAccessToken -ResourceUrl https://database.windows.net -AsSecureString).Token
    $access_token = [System.Net.NetworkCredential]::new("", $access_tokenSecStr).Password
    Write-Host "Access token retrieved"

    Write-Host "Load SystemStatus from SQL Server"
    $SystemStatusDb = Invoke-Sqlcmd `
                        -ServerInstance $Settings["SC_AZURE_SQL_SERVER_NAME"] `
                        -Database $Settings["SC_AZURE_SQL_DATABASE_NAME"] `
                        -AccessToken $access_token `
                        -query 'SELECT *
                                FROM [dbo].[SystemStatus] WHERE [ID] = 1'

    if($SystemStatusDb.IsFirstRunCompleted -ne 1){
        Write-Host "First Run Wizard is not yet completed, skip processing jobs"
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [System.Net.HttpStatusCode]::BadRequest
            Body = "First Run Wizard is not yet completed, skip processing jobs"
        })
        exit 
    }
    if($SystemStatusDb.DomainControllerStatus -ne 3){
        Write-Host "Domain Controller is not yet ready, skip processing jobs"
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [System.Net.HttpStatusCode]::BadRequest
            Body = "Domain Controller is not yet ready, skip processing jobs"
        })
        exit 
    }

    Write-Host "Load KeyVault Secrets"
    $Settings.Add("AdminUsername", (Get-AzKeyVaultSecret -VaultName $Settings["KEYVAULT_NAME"] -Name "AdminUsername" -AsPlainText))
    $Settings.Add("AdminDcPassword", (Get-AzKeyVaultSecret -VaultName $Settings["KEYVAULT_NAME"] -Name "AdminDcPassword").SecretValue)
    $Settings.Add("AdminWorkerPassword", (Get-AzKeyVaultSecret -VaultName $Settings["KEYVAULT_NAME"] -Name "AdminWorkerPassword").SecretValue)

    
    Write-Host "Update Job from SQL Server"
    $Job = Invoke-Sqlcmd `
        -ServerInstance $Settings["SC_AZURE_SQL_SERVER_NAME"] `
        -Database $Settings["SC_AZURE_SQL_DATABASE_NAME"] `
        -AccessToken $access_token `
        -MaxCharLength 80000 `
        -query "UPDATE 
                    [dbo].[TestJob]
                SET 
                    [TestOutput] = CONCAT([TestOutput], '$($TestOutput.Replace("'", "''"))'),
                    [SchedulerLog] = CONCAT([SchedulerLog], '$($ExecutorOutput.Replace("'", "''"))'),
                    [Status] = $status
                WHERE 
                    [Status] IN(1,2,3)
                    AND [WorkerName] = '$workername'"
    Write-Host "Job updated '$Job'"
    
    

    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::OK
        ContentType = "application/json"
        Body = $data
    })
    
    
}

