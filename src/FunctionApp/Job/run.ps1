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


[string]$workername = [string]($Request.Query.workername)


if(-not $workername -or $workername.length -eq 0) {
    Write-Error "Invalid workername"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::BadRequest
        Body = "Invalid workername or no workername specified"
    })
} else {
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

    
    Write-Host "Load Job from SQL Server"
    $Job = Invoke-Sqlcmd `
        -ServerInstance $Settings["SC_AZURE_SQL_SERVER_NAME"] `
        -Database $Settings["SC_AZURE_SQL_DATABASE_NAME"] `
        -AccessToken $access_token `
        -MaxCharLength 80000 `
        -query "SELECT 
            t.[ID],
            u.[Name],
            u.[OperatingSystem],
            u.[ScriptTest],
            u.[ScriptPrerequisites],
            u.[ScriptCleanup],
            u.[ElevationRequired],
            u.[ExecutorSystemType],
            u.[ExecutorUserType]
        FROM 
            [dbo].[TestJob] AS t
        INNER JOIN 
            [dbo].[TestDefinition] AS u 
            ON t.[UseCaseID] = u.[ID]
        WHERE [Status] = 2 
            AND
             t.[WorkerName] = '$workername'"
    Write-Host "Job loaded '$($Job.ID)'"
    if($null -eq $Job){
        Write-Host "No job found for workername '$workername'"
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [System.Net.HttpStatusCode]::NotFound
            Body = "No job found for workername '$workername'"
        })
        exit 
    } else {
        Write-Host "Job found for workername '$workername'"
        $JobObj = [PSCustomObject] @{
            ID = $Job.ID
            Name = $Job.Name
            OperatingSystem = $Job.OperatingSystem
            ScriptPrerequisites = if([String]::IsNullOrEmpty($Job.ScriptPrerequisites)){""}else{$Job.ScriptPrerequisites}
            ScriptTest = if([String]::IsNullOrEmpty($Job.ScriptTest)){""}else{$Job.ScriptTest}
            ScriptCleanup = if([String]::IsNullOrEmpty($Job.ScriptCleanup)){""}else{$Job.ScriptCleanup}
            ElevationRequired = $Job.ElevationRequired
            ExecutorSystemType = $Job.ExecutorSystemType
            ExecutorUserType = $Job.ExecutorUserType
            Username = ""
            Password = ""
            Domain = ""
        }
        if($JobObj.ExecutorUserType -eq 1){
            $JobObj.Username = $Settings["AdminUsername"]
            $JobObj.Password = $Settings["AdminWorkerPassword"]
            $JobObj.Domain = ""
        } 
        if($JobObj.ExecutorUserType -eq 2){
            $JobObj.Username = $Settings["AdminUsername"]
            $JobObj.Password = $Settings["AdminDcPassword"]
            $JobObj.Domain = $Settings["SC_DOMAIN_FQDN"]
        } 
        if($JobObj.ExecutorUserType -eq 3){
            $JobObj.Username = "Tester"
            $JobObj.Password = $Settings["AdminDcPassword"]
            $JobObj.Domain = $Settings["SC_DOMAIN_FQDN"]
        }
        if($Job.OperatingSystem -eq 0){
            $JobObj.ScriptPrerequisites = "gpupdate /force" + [Environment]::NewLine +"Update-MpSignature -Verbose" + [Environment]::NewLine + $JobObj.ScriptPrerequisites
        } 
        $data = $JobObj | ConvertTo-Json
        Write-Host "Job loaded with length $($data.Length)"


        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [System.Net.HttpStatusCode]::OK
            ContentType = "application/json"
            Body = $data
        })
    }
    
}

