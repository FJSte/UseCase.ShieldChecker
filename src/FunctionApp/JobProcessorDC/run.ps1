# Define a parameter named $Timer, typically used for a timer-based trigger in PowerShell automation
param($Timer)
# Output the current date and time to the console, indicating when the script is run
Write-Output "JobProcessorDC Timer trigger function executed at: $(Get-Date)"

#region Functions

enum JobStatus
{
    Queued
    WaitingForMDE
    WaitingForDetection
    ReviewPending
    ReviewDone
    Completed
    Canceled
    Error
}
enum JobResult
{
    Success
    SuccessWithOtherDetection
    Failed
    Undetermined
}

$Mutex = [guid]::NewGuid().ToString()

function Invoke-CheckMutex {
    param(
    )
    $MutexDb = Invoke-Sqlcmd `
                    -ServerInstance $Settings["SC_AZURE_SQL_SERVER_NAME"] `
                    -Database $Settings["SC_AZURE_SQL_DATABASE_NAME"] `
                    -AccessToken $access_token_sql `
                    -query "SELECT * FROM [dbo].[SchedulerMutex] WHERE [SchedulerType] = 0 AND [Owner] != '$Mutex' AND [Start] > DATEADD(minute,-35,GETUTCDATE())"
    if($MutexDb.Count -eq 0) {
        Write-Host "No other worker is processing jobs, set mutex"
        Invoke-Sqlcmd `
                    -ServerInstance $Settings["SC_AZURE_SQL_SERVER_NAME"] `
                    -Database $Settings["SC_AZURE_SQL_DATABASE_NAME"] `
                    -AccessToken $access_token_sql `
                    -query "INSERT INTO [dbo].[SchedulerMutex] ([Owner],[Start],[SchedulerType]) VALUES ('$Mutex',GETUTCDATE(),0)"
        return $true
    } else 
    {
        return $false
    }
}
function Invoke-ReleaseMutex {
    param(
    )
    Write-Host "Release Mutex"
    Invoke-Sqlcmd `
        -ServerInstance $Settings["SC_AZURE_SQL_SERVER_NAME"] `
        -Database $Settings["SC_AZURE_SQL_DATABASE_NAME"] `
        -AccessToken $access_token_sql `
        -query "DELETE
                FROM [dbo].[SchedulerMutex] WHERE [SchedulerType] = 0 AND [Owner] = '$Mutex'"
    
}
function Enable-PublicAccess {
    param(
    )
    if([String]::IsNullOrWhiteSpace($j.WorkerRemoteIP)){
        if((Get-AzPublicIpAddress -Name "$($j.WorkerName)-pip" -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"])){
            $pip = Get-AzPublicIpAddress -Name "$($j.WorkerName)-pip" -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"]
        } else {
            $pip = New-AzPublicIpAddress -Name "$($j.WorkerName)-pip" -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] -AllocationMethod Static -Location $Settings["SC_AZ_LOCATION"]
            Write-Log -JobId $j.Id -Mutex $Mutex -Text "Public IP '$($pip.IpAddress)' created"
        }
        $nsg = Get-AzNetworkSecurityGroup -Name "nsg-$($Settings["SC_APP_NAME"])-$($Settings["SC_DEPLOY_ENVIRONMENT"])-001" -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"]
        Write-Log -JobId $j.Id -Mutex $Mutex -Text "Network Security Group '$($nsg.Name)' found"

        $vm = Get-AzVM -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] -Name $Settings["DomainControllerName"]
        
        $nic = Get-AzNetworkInterface -ResourceId $vm.NetworkProfile.NetworkInterfaces[0] -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"]
        $vm = Get-AzVM -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] -Name $VMName
        $vm.NetworkProfile.NetworkInterfaces[0]
        $nic = Get-AzNetworkInterface -ResourceId $vm.NetworkProfile.NetworkInterfaces[0].Id
        $nic | Set-AzNetworkInterfaceIpConfig -Name ipconfig1 -PublicIPAddress $pip
        $nic.NetworkSecurityGroup = $nsg
        $nic | Set-AzNetworkInterface 
        Write-Log -JobId $j.Id -Mutex $Mutex -Text "Public Access enabled for VM '$($j.WorkerName)'"
    } else {
        Write-Log -JobId $j.Id -Mutex $Mutex -Text "Public Access was already enabled for VM '$($j.WorkerName)'"
        $pip = Get-AzPublicIpAddress -Name "$($j.WorkerName)-pip" -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"]
    }
    return $pip
}

function Write-Log {
    param(
        [string]$Text,
        [string]$JobId,
        [string]$Mutex,
        [ValidateSet("Info","Warning","Error")]
        [string]$Type = "Info"
    )
    If($Type -eq "Info") {
        Write-Host "$Mutex - $JobId - $(Get-Date -Format o) - $Text"
    } elseif ($Type -eq "Warning") {
        Write-Warning "$Mutex - $JobId - $(Get-Date -Format o) - $Text" -WarningAction Continue
    } elseif ($Type -eq "Error") {
        Write-Error "$Mutex - $JobId - $(Get-Date -Format o) - $Text" -ErrorAction Continue
    }
    $script:Log += "$Mutex - $JobId - $(Get-Date -Format o) - $Type - $Text`r`n"

}

function Get-MdeMachine {
    param(
        [string]$MachineName,
        [string]$access_token_mde
    )
    $headers = @{ 
        'Content-Type' = 'application/json'
        'Accept' = 'application/json'
        'Authorization' = "Bearer $access_token_mde" 
    }
    $apiUrl = "https://api.security.microsoft.com/api/machines?`$filter=startswith(computerDnsName,'$($j.WorkerName)')"
    $response = Invoke-RestMethod -Method Get -Uri $apiUrl -Headers $headers
    return $response.value[0].id
}
function Set-MdeMachineTag {
    param(
        [string]$MachineId,
        [string]$access_token_mde
    )
    $headers = @{ 
        'Content-Type' = 'application/json'
        'Accept' = 'application/json'
        'Authorization' = "Bearer $access_token_mde" 
    }
    $apiUrl = "https://api.security.microsoft.com/api/machines/$MachineId/tags"
    $Body = @{"Value"="baseVISION-ShieldChecker";"Action"="Add"}
    $Body = $Body | ConvertTo-Json
    $response = Invoke-RestMethod -Method Post -Headers $headers -Body $body -Uri $apiUrl
    return $response
}


function Get-Alerts {
    param(
        [string]$MachineName,
        [string]$WorkerIp,
        [string]$access_token_graph
    )
    $headers = @{ 
        'Content-Type' = 'application/json'
        'Accept' = 'application/json'
        'Authorization' = "Bearer $access_token_graph" 
    }
    $apiUrl = "https://graph.microsoft.com/beta/security/alerts_v2?`$filter=lastUpdateDateTime ge $([DateTime]::UtcNow.AddHours(-2).ToString("yyyy-MM-ddTHH:mm:ssZ"))"
    $response = Invoke-RestMethod -Method Get -Headers $headers -Uri $apiUrl
    $foundAlerts = @()
    foreach ($alert in $response.value){
        Write-Host "Alert: $($alert.title)"
        $DevicePartOfAlert = $false
        foreach($evidence in $alert.evidence){
    
                if($null -ne $evidence.hostName -and $evidence.hostName.StartsWith($MachineName)){
                    Write-Host "Alert is from test machine $MachineName"
                    $DevicePartOfAlert = $true
                }
                if($null -ne $evidence.lastIpAddress -and $evidence.lastIpAddress -eq $WorkerIp){
                    Write-Host "Alert is from test machine $WorkerIp"
                    $DevicePartOfAlert = $true
                }
                if($null -ne $evidence.ipAddress -and $evidence.ipAddress -eq $WorkerIp){
                    Write-Host "Alert is from test machine $WorkerIp"
                    $DevicePartOfAlert = $true
                }

        }
        if($DevicePartOfAlert -eq $true){
            $foundAlerts += $alert
        }
    }
    return $foundAlerts
}


function Update-JobStatus {
    param(
        [int]$JobId,
        [JobStatus]$Status,
        [Parameter(Mandatory=$false)]
        [JobResult]$Result,
        [Parameter(Mandatory=$false)]
        [string]$WorkerName,
        [Parameter(Mandatory=$false)]
        [string]$WorkerIP,
        [Parameter(Mandatory=$false)]
        [string]$WorkerRemoteIP,
        [Parameter(Mandatory=$false)]
        [bool]$WorkerStart = $false,
        [Parameter(Mandatory=$false)]
        [bool]$WorkerEnd = $false,
        [Parameter(Mandatory=$false)]
        [string]$TestUser,
        [Parameter(Mandatory=$false)]
        [string]$TestOutput,
        [Parameter(Mandatory=$false)]
        [string]$DetectedAlerts,
        [Parameter(Mandatory=$false)]
        [string]$SchedulerLog,
        [Parameter(Mandatory=$false)]
        [string]$access_token_sql
    )
    $UpdateSql = @()
    if($WorkerStart -eq $true){
        $UpdateSql += "[WorkerStart]=GETUTCDATE()"
    }
    if($WorkerEnd -eq $true){
        $UpdateSql += "[WorkerEnd]=GETUTCDATE()"
    }
    if($null -ne $Result){
        $UpdateSql += "[Result]=$([int]$Result)"
    }
    if([string]::IsNullOrEmpty($WorkerName) -eq $false){
        $UpdateSql += "[WorkerName]='$($WorkerName.Replace("'", "''"))'"
    }
    if([string]::IsNullOrEmpty($WorkerIP) -eq $false){
        $UpdateSql += "[WorkerIP]='$($WorkerIP.Replace("'", "''"))'"
    }
    if([string]::IsNullOrEmpty($WorkerRemoteIP) -eq $false){
        $UpdateSql += "[WorkerRemoteIP]='$($WorkerRemoteIP.Replace("'", "''"))'"
    }
    if([string]::IsNullOrEmpty($TestUser) -eq $false){
        $UpdateSql += "[TestUser]='$($TestUser.Replace("'", "''"))'"
    }
    if([string]::IsNullOrEmpty($TestOutput) -eq $false){
        $UpdateSql += "[TestOutput]='$($TestOutput.Replace("'", "''"))'"
    }
    if([string]::IsNullOrEmpty($DetectedAlerts) -eq $false){
        $UpdateSql += "[DetectedAlerts]='$($DetectedAlerts.Replace("'", "''"))'"
    }
    if([string]::IsNullOrEmpty($SchedulerLog) -eq $false){
        $UpdateSql += "[SchedulerLog]='$($SchedulerLog.Replace("'", "''"))'"
    }
    $UpdateSql = $UpdateSql -join ", "
    Invoke-Sqlcmd `
        -ServerInstance $Settings["SC_AZURE_SQL_SERVER_NAME"] `
        -Database $Settings["SC_AZURE_SQL_DATABASE_NAME"] `
        -AccessToken $access_token_sql `
        -query "Update 
                    [dbo].[TestJob] 
                SET 
                    [Status] = $([int]$Status),
                    [Modified] = GETUTCDATE(),
                    $UpdateSql  
                WHERE 
                    [ID] = $JobId"
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
$access_token_mde_SecStr  = (Get-AzAccessToken -ResourceUrl https://api.securitycenter.microsoft.com -AsSecureString).Token
$access_token_mde = [System.Net.NetworkCredential]::new("", $access_token_mde_SecStr).Password
$access_token_graph_SecStr  = (Get-AzAccessToken -ResourceUrl https://graph.microsoft.com -AsSecureString).Token
$access_token_graph = [System.Net.NetworkCredential]::new("", $access_token_graph_SecStr).Password

Write-Host "Load SystemStatus from SQL Server"
$SystemStatusDb = Invoke-Sqlcmd `
                    -ServerInstance $Settings["SC_AZURE_SQL_SERVER_NAME"] `
                    -Database $Settings["SC_AZURE_SQL_DATABASE_NAME"] `
                    -AccessToken $access_token_sql `
                    -query 'SELECT *
                            FROM [dbo].[SystemStatus] WHERE [ID] = 1'

if($SystemStatusDb.IsFirstRunCompleted -ne 1){
    Write-Host "First Run Wizard is not yet completed, skip processing jobs"
    exit 
}
if($SystemStatusDb.DomainControllerStatus -ne 3){
    Write-Host "Domain Controller is not yet ready, skip processing jobs"
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

Write-Host "Load KeyVault Secrets"
$Settings.Add("AdminUsername", (Get-AzKeyVaultSecret -VaultName $Settings["KEYVAULT_NAME"] -Name "AdminUsername" -AsPlainText))
$Settings.Add("AdminDcPassword", (Get-AzKeyVaultSecret -VaultName $Settings["KEYVAULT_NAME"] -Name "AdminDcPassword").SecretValue)
$Settings.Add("AdminWorkerPassword", (Get-AzKeyVaultSecret -VaultName $Settings["KEYVAULT_NAME"] -Name "AdminWorkerPassword").SecretValue)

$Settings.GetEnumerator() | ForEach-Object {
    Write-Host "Setting: $($_.Key) = $("$($_.Value)".SubString(0, [System.Math]::Min(128, "$($_.Value)".Length)))" 
}
#endregion load settings


#region process jobs
Write-Host "Load active Jobs from SQL Server"
try{
    
    $RunningJobs = Invoke-Sqlcmd `
                        -ServerInstance $Settings["SC_AZURE_SQL_SERVER_NAME"] `
                        -Database $Settings["SC_AZURE_SQL_DATABASE_NAME"] `
                        -AccessToken $access_token_sql `
                        -query "SELECT TOP (1000) 
                                t.[ID],
                                [UseCaseID],
                                t.[Created],
                                t.[Modified],
                                [WorkerStart],
                                [WorkerEnd],
                                [Status],
                                [Result],
                                [WorkerName],
                                [WorkerIP],
                                [WorkerRemoteIP],
                                [TestUser],
                                [TestOutput],
                                [DetectedAlerts],
                                [SchedulerLog],
                                u.[ElevationRequired],
                                u.[OperatingSystem],
                                u.[ExpectedAlertTitle],
                                u.[ExecutorSystemType],
                                u.[ExecutorUserType],
                                u.[Name]
                            FROM 
                                [dbo].[TestJob] AS t
                            INNER JOIN 
                                [dbo].[TestDefinition] AS u 
                                ON t.[UseCaseID] = u.[ID]
                            WHERE 
                                [Status] NOT IN ($([int]([JobStatus]::Completed)), $([int]([JobStatus]::Error))) 
                                AND u.[Enabled] = 1
                                AND u.[ExecutorSystemType] = 1
                            ORDER BY 
                                t.[Created] ASC"
    Write-Host "Found $($RunningJobs.Count) jobs in queue ready to start";
    if($RunningJobs.Count -gt 0){
        if($RunningJobs.Count -eq 1) {
            $j = $RunningJobs 
        } else {
            $j = $RunningJobs[0]
        }
        $j
        if([string]::IsNullOrWhiteSpace($j.SchedulerLog) -or $j.SchedulerLog -eq "" -or $j.SchedulerLog -is [DBNull]){
            $script:Log = ""
        } else {
            $script:Log = $j.SchedulerLog
        }
    
        Write-Log -JobId $j.Id -Mutex $Mutex -Text "Processing job with Status $($j.Status) $([JobStatus].GetEnumName($j.Status))"

        switch ([JobStatus].GetEnumName($j.Status)) {
            "Queued" {
                try{
                    Write-Log -JobId $j.Id -Mutex $Mutex -Text "Job $($j.Id) is queued start create VM"
                    if([string]::IsNullOrEmpty($j.WorkerName) ){
                        Write-Log -JobId $j.Id -Mutex $Mutex -Text "No WorkerName set, assign Domain Controller VM name to job"
                        $VMName = $Settings["DomainControllerName"]
                        Update-JobStatus -JobId $j.Id -Status ([JobStatus]::Queued) -WorkerName $VMName -access_token_sql $access_token_sql
                    } else {
                        Write-Log -JobId $j.Id -Mutex $Mutex -Text "WorkerName is set"
                        $VMName = $j.WorkerName
                    }
                    $vm = Get-AzVM -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] -Name $VMName
                    $NIC = Get-AzNetworkInterface -ResourceId $vm.NetworkProfile.NetworkInterfaces[0].Id
                        
                    
                    # Update Job Status
                    Update-JobStatus -JobId $j.Id -Status ([JobStatus]::WaitingForDetection) -WorkerName $VMName -WorkerIP $($NIC.IpConfigurations[0].PrivateIpAddress) -WorkerStart $true -SchedulerLog $script:Log -access_token_sql $access_token_sql

                } catch {
                    Write-Log -JobId $j.Id -Mutex $Mutex -Text "Error processing job: $_" -Type "Error"
                    # Update Job Status
                    Update-JobStatus -JobId $j.Id -Status ([JobStatus]::Error) -SchedulerLog $script:Log -WorkerEnd $true -access_token_sql $access_token_sql
                    
                }
                
            }
            
            "WaitingForDetection" {
                Write-Host "Job $($j.Id) is waiting for detection";
                try{
                    # Set to Review pending when time is over since Worker Start ore than 2 hours
                    if([datetime]($j.WorkerStart) -lt ([DateTime]::UtcNow).AddMinutes(-1 * $Settings["JobTimeout"])){
                        Write-Log -JobId $j.Id -Mutex $Mutex -Text "Job $($j.Id) is waiting for detection, but time is over $($Settings["JobTimeout"]) Minutes"
                        if($Settings["JobReview"] -eq 1){
                            Write-Log -JobId $j.Id -Mutex $Mutex -Text "Set Pending Review"
                            Write-Log -JobId $j.Id -Mutex $Mutex -Text "Assigning Public IP to VM"
                            $pip= Enable-PublicAccess
                            # Update Job Status
                            Update-JobStatus -JobId $j.Id -Status ([JobStatus]::ReviewPending) -Result ([JobResult]::Failed) -WorkerRemoteIP $pip.IpAddress -SchedulerLog $script:Log -access_token_sql $access_token_sql
                        } else {
                            Write-Log -JobId $j.Id -Mutex $Mutex -Text "Review is not enabled, set job to Completed with failed detection"
                            # Update Job Status
                            Update-JobStatus -JobId $j.Id -Status ([JobStatus]::Completed) -Result ([JobResult]::Failed) -WorkerEnd $true -SchedulerLog $script:Log -access_token_sql $access_token_sql
                        }

                        
                    } else {
                        Write-Log -JobId $j.Id -Mutex $Mutex -Text "Job $($j.Id) is waiting for detection, check if detection is done"
                        $foundAlerts = Get-Alerts -MachineName $j.WorkerName -access_token_graph $access_token_graph
                        # Check if detection is done
                        if($foundAlerts.Count -gt 0){
                            Write-Log -JobId $j.Id -Mutex $Mutex -Text "Detection is done with $($foundAlerts.Count) alerts"
                            
                            if($foundAlerts.title -contains $j.ExpectedAlertTitle){
                                $result = [JobResult]::Success
                            } else {
                                $result = [JobResult]::SuccessWithOtherDetection
                            }
                            
                            # Update Job Status
                            Update-JobStatus -JobId $j.Id -Status ([JobStatus]::Completed) -Result $result -SchedulerLog $script:Log -WorkerEnd $true -DetectedAlerts ($foundAlerts | ConvertTo-Json -Depth 5) -access_token_sql $access_token_sql
                            
                        } else {
                            Write-Log -JobId $j.Id -Mutex $Mutex -Text "Detection is not yet done"
                            # Update Job Status
                            Update-JobStatus -JobId $j.Id -Status ([JobStatus]::WaitingForDetection) -SchedulerLog $script:Log -access_token_sql $access_token_sql
                        }
                    }
                } catch {
                    Write-Log -JobId $j.Id -Mutex $Mutex -Text "Error processing job: $_" -Type "Error"
                    # Update Job Status
                    Update-JobStatus -JobId $j.Id -Status ([JobStatus]::Error) -SchedulerLog $script:Log -WorkerEnd $true -access_token_sql $access_token_sql
                }                 
            }
            "ReviewPending" {
                Write-Host "Job $($j.Id) is pending review";
            }
            "ReviewDone" {
                try {
                    Write-Log -JobId $j.Id -Mutex $Mutex -Text "Job $($j.Id) is pending done"
                    # Update Job Status
                    Update-JobStatus -JobId $j.Id -Status ([JobStatus]::Completed) -SchedulerLog $script:Log -WorkerEnd $true -access_token_sql $access_token_sql
                } catch {
                    Write-Log -JobId $j.Id -Mutex $Mutex -Text "Error processing job: $_" -Type "Error"
                    # Update Job Status
                    Update-JobStatus -JobId $j.Id -Status ([JobStatus]::Error) -SchedulerLog $script:Log -WorkerEnd $true -access_token_sql $access_token_sql
                }
                $vm = Get-AzVM -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] -Name $Settings["DomainControllerName"]
        
                # Remove Remote network access
                $nic = Get-AzNetworkInterface -ResourceId $vm.NetworkProfile.NetworkInterfaces[0] -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"]
                $nic | Set-AzNetworkInterfaceIpConfig -Name ipconfig1 -PublicIPAddress $null
                $nic.NetworkSecurityGroup = $null
                $nic | Set-AzNetworkInterface 
            }
            "Completed" {
                Write-Host "Job $($j.Id) completed";
            }
            "Canceled" {
                Write-Host "Job $($j.Id) was canceled";
                Write-Log -JobId $j.Id -Mutex $Mutex -Text "Job $($j.Id) is canceled"
                # Update Job Status
                Update-JobStatus -JobId $j.Id -Status ([JobStatus]::Completed) -SchedulerLog $script:Log -WorkerEnd $true -access_token_sql $access_token_sql
            }
            default {
                Write-Host "Unknown status $($j.Status)";
            }
        }
    }
        
} catch {
    Write-Host "Error processing jobs: $_"
}

#end region process jobs
