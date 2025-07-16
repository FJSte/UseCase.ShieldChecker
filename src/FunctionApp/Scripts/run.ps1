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


[int]$OS = [int]($Request.Query.os)

if($OS -ne 0 -and $OS -ne 1) {
    Write-Error "Invalid OS"
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::BadRequest
        Body = "Invalid OS specified"
    })
} else {
    Write-Host "Connecting to Azure with Managed Identity"
    Connect-AzAccount -Identity -AccountId $Settings["AZURE_CLIENT_ID"]
    Write-Host "Connected to Azure"

    Write-Host "Retrieving access token for SQL Server"     
    $access_tokenSecStr  = (Get-AzAccessToken -ResourceUrl https://database.windows.net -AsSecureString).Token
    $access_token = [System.Net.NetworkCredential]::new("", $access_tokenSecStr).Password
    Write-Host "Access token retrieved"


    Write-Host "Load Job from SQL Server"
    $Settings = Invoke-Sqlcmd `
        -ServerInstance $Settings["SC_AZURE_SQL_SERVER_NAME"] `
        -Database $Settings["SC_AZURE_SQL_DATABASE_NAME"] `
        -AccessToken $access_token `
        -MaxCharLength 80000 `
        -query "SELECT 
            Id,
            CAST(s.[MDEWindowsOnboardingScript] AS NVARCHAR(MAX)) AS [MDEWindowsOnboardingScript],
            CAST(s.[MDELinuxOnboardingScript] AS NVARCHAR(MAX)) AS [MDELinuxOnboardingScript]
        FROM 
            [dbo].[Settings] as s
        WHERE 
            s.Id = 1"
    Write-Host "Settings loaded '$($Settings.Id)'"
    
    if($OS -eq 0){
        $data = $Settings.MDEWindowsOnboardingScript
        Write-Host "MDE Windows Onboarding Script loaded with length $($data.Length)"
        $filename = "MDE-Onboarding.cmd"  
    } elseif ($OS -eq 1) 
    {
        $data = $Settings.MDELinuxOnboardingScript
        Write-Host "MDE Linux Onboarding Script loaded with length $($data.Length)"
        $filename = "MDE-Onboarding.sh"
    } else {
        Write-Error "Invalid OS specified"
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [System.Net.HttpStatusCode]::BadRequest
            Body = "Invalid OS specified"
        })
        exit
    }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [System.Net.HttpStatusCode]::OK
        ContentType = "application/octet-stream"
        Headers     = @{
            'Content-Disposition' = "attachment; filename=`"$filename`"" # To set the filename of the download
        }
        Body = $data
    })

}

