# Define a parameter named $Timer, typically used for a timer-based trigger in PowerShell automation
param($Timer)
# Output the current date and time to the console, indicating when the script is run
Write-Output "JobProcessorWorker Timer trigger function executed at: $(Get-Date)"

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

function Invoke-MdeMachineOffboard {
    param(
        [string]$MachineId,
        [string]$access_token_mde
    )
    $headers = @{ 
        'Content-Type' = 'application/json'
        'Accept' = 'application/json'
        'Authorization' = "Bearer $access_token_mde" 
    }
    $apiUrl = "https://api.security.microsoft.com/api/machines/$MachineId/offboard"
    $Body = @{"Comment"="Offboard by Shield Checker"}
    $Body = $Body | ConvertTo-Json
    $response = Invoke-RestMethod -Method Post -Headers $headers -Body $body -Uri $apiUrl -SkipHttpErrorCheck -ErrorAction SilentlyContinue 
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

function Enable-PublicAccess {
    param(
    )
    if([String]::IsNullOrWhiteSpace($j.WorkerRemoteIP)){
        $pip = New-AzPublicIpAddress -Name "$($j.WorkerName)-pip" -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] -AllocationMethod Static -Location $Settings["SC_AZ_LOCATION"]
        Write-Log -JobId $j.Id -Mutex $Mutex -Text "Public IP '$($pip.IpAddress)' created"

        $nsg = Get-AzNetworkSecurityGroup -Name "nsg-$($Settings["SC_APP_NAME"])-$($Settings["SC_DEPLOY_ENVIRONMENT"])-001" -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"]
        Write-Log -JobId $j.Id -Mutex $Mutex -Text "Network Security Group '$($nsg.Name)' found"

        $nic = Get-AzNetworkInterface -Name "$($j.WorkerName)-nic" -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"]
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

function Remove-Worker{
    try{
        Write-Log -JobId $j.Id -Mutex $Mutex -Text "Stop VM '$($j.WorkerName)'"
        Stop-AzVM -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] -Name $j.WorkerName -Force -ErrorAction SilentlyContinue
        $vm = Get-AzVM -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] -Name $j.WorkerName -ErrorAction SilentlyContinue
        
        Write-Log -JobId $j.Id -Mutex $Mutex -Text "Remove VM '$($j.WorkerName)'"
        Remove-AzVM -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] -Name $j.WorkerName -Force -ForceDeletion $true -ErrorAction SilentlyContinue
        Write-Log -JobId $j.Id -Mutex $Mutex -Text "Remove NIC '$($j.WorkerName)-nic'"
        Remove-AzNetworkInterface -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] -Name "$($j.WorkerName)-nic" -Force -ErrorAction SilentlyContinue
        Write-Log -JobId $j.Id -Mutex $Mutex -Text "Remove Public IP '$($j.WorkerName)-pip'"
        Remove-AzPublicIpAddress -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] -Name "$($j.WorkerName)-pip" -Force -ErrorAction SilentlyContinue
        if($null -ne $vm -and $null -ne $vm.StorageProfile.OsDisk.Name){
            Write-Log -JobId $j.Id -Mutex $Mutex -Text "Remove Disk '$($vm.StorageProfile.OsDisk.Name)'"
            Remove-AzDisk -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] -DiskName $vm.StorageProfile.OsDisk.Name -Force -ErrorAction SilentlyContinue
        }
        Write-Log -JobId $j.Id -Mutex $Mutex -Text "Offboard from MDE"
        $MachineId = Get-MdeMachine -MachineName $j.WorkerName -access_token_mde $access_token_mde
        $mderesult = Invoke-MdeMachineOffboard -MachineId $MachineId -access_token_mde $access_token_mde
        Write-Log -JobId $j.Id -Mutex $Mutex -Text "Offboard from MDE result: $($mderesult)"
    } catch {
        Write-Log -JobId $j.Id -Mutex $Mutex -Text "Error: $($_.Exception.Message), but continue" -Type "Error"
    }
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
        [string]$DefenderMachineId,
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
    if([string]::IsNullOrEmpty($DefenderMachineId) -eq $false){
        $UpdateSql += "[DefenderMachineId]='$($DefenderMachineId.Replace("'", "''"))'"
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
    if(Invoke-CheckMutex){
        Start-Sleep -Seconds (Get-Random -Minimum 0 -Maximum 20)
        if(Invoke-CheckMutex){
        $RunningJobs = Invoke-Sqlcmd `
                            -ServerInstance $Settings["SC_AZURE_SQL_SERVER_NAME"] `
                            -Database $Settings["SC_AZURE_SQL_DATABASE_NAME"] `
                            -AccessToken $access_token_sql `
                            -query "SELECT TOP ($($Settings["MaxWorkerCount"]))
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
                                    AND u.[ExecutorSystemType] = 0
                                ORDER BY 
                                    t.[Created] ASC"
        Write-Host "Found $($RunningJobs.Count) jobs in queue ready to start";

        foreach($j in $RunningJobs) {
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
                            Write-Log -JobId $j.Id -Mutex $Mutex -Text "No WorkerName set, define new VM name"
                            $VMName = "wrk-$([Guid]::NewGuid().ToString().Substring(0, 11))"
                            Update-JobStatus -JobId $j.Id -Status ([JobStatus]::Queued) -WorkerName $VMName -access_token_sql $access_token_sql
                        } else {
                            Write-Log -JobId $j.Id -Mutex $Mutex -Text "WorkerName is set, use existing VM"
                            $VMName = $j.WorkerName
                        }
                        if(Get-AzVM -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] -Name $VMName -ErrorAction SilentlyContinue){
                            Write-Log -JobId $j.Id -Mutex $Mutex -Text "VM with name '$VMName' already exists, continue to extensions"
                            $NIC = Get-AzNetworkInterface -Name "$VMName-nic" -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"]
                        } else {
                            Write-Log -JobId $j.Id -Mutex $Mutex -Text "Create VM with name '$VMName'"
                            
                            $NIC = Get-AzNetworkInterface -Name "$VMName-nic" -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] -ErrorAction SilentlyContinue
                            if($null -eq $NIC){
                                $NIC = New-AzNetworkInterface -Name "$VMName-nic" -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] -Location $Settings["SC_AZ_LOCATION"] -SubnetId $Settings["SC_AZ_WORKER_SUBNET_ID"] -DnsServer '10.0.3.10'
                            } else {
                                Write-Log -JobId $j.Id -Mutex $Mutex -Text "NIC with name '$($NIC.Name)' already exists, continue to VM creation"
                            }
                            
                            $Credential = New-Object System.Management.Automation.PSCredential ($Settings["AdminUsername"], $Settings["AdminWorkerPassword"]);
                            
                            $VirtualMachine = New-AzVMConfig -VMName $VMName -VMSize $Settings["WorkerVMSize"] -IdentityType None -EnableSecureBoot $true -EnableVtpm $true -Tags @{ShieldChecker="Worker"}
                            $VirtualMachine = Add-AzVMNetworkInterface -VM $VirtualMachine -Id $NIC.Id -DeleteOption Delete
                            if($j.OperatingSystem -eq 0){
                                $VirtualMachine = Set-AzVMOperatingSystem -VM $VirtualMachine -Windows -ComputerName $VMName -Credential $Credential -ProvisionVMAgent -EnableAutoUpdate
                                $VirtualMachine = Set-AzVMSourceImage -VM $VirtualMachine -PublisherName ($Settings["WorkerVMWindowsImage"] -split(":"))[0] -Offer ($Settings["WorkerVMWindowsImage"] -split(":"))[1] -Skus ($Settings["WorkerVMWindowsImage"] -split(":"))[2] -Version ($Settings["WorkerVMWindowsImage"] -split(":"))[3] 
                            } else {
                                $VirtualMachine = Set-AzVMOperatingSystem -VM $VirtualMachine -Linux -ComputerName $VMName -Credential $Credential
                                $VirtualMachine = Set-AzVMSourceImage -VM $VirtualMachine -PublisherName ($Settings["WorkerVMLinuxImage"] -split(":"))[0] -Offer ($Settings["WorkerVMLinuxImage"] -split(":"))[1] -Skus ($Settings["WorkerVMLinuxImage"] -split(":"))[2] -Version ($Settings["WorkerVMLinuxImage"] -split(":"))[3] 
                            }
                            
                            $VirtualMachine = Set-AzVMBootDiagnostic -VM $VirtualMachine -Disable
                            try{
                                $r = New-AzVM `
                                    -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] `
                                    -Location $Settings["SC_AZ_LOCATION"] `
                                    -VM $VirtualMachine `
                                    -Verbose `
                                    -ErrorAction Stop 

                                Write-Log -JobId $j.Id -Mutex $Mutex -Text "Create VM result '$($r.StatusCode)'"

                                Write-Log -JobId $j.Id -Mutex $Mutex -Text "Adjust DeleteOption on Disks and Networkcard"
                                $vmConfig = Get-AzVM -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] -Name $VMName
                                $vmConfig.StorageProfile.OsDisk.DeleteOption = 'Delete'
                                $vmConfig.StorageProfile.DataDisks | ForEach-Object { $_.DeleteOption = 'Delete' }
                                $vmConfig.NetworkProfile.NetworkInterfaces | ForEach-Object { $_.DeleteOption = 'Delete' }
                                $vmConfig | Update-AzVM
                                Write-Log -JobId $j.Id -Mutex $Mutex -Text "Adjusted DeleteOption on Disks and Networkcard"

                            } catch  {
                                if($_ -like "*Total Regional Cores quota*" -or $_.ErrorMessage -like "*Total Regional Cores quota*"){
                                    Write-Log -JobId $j.Id -Mutex $Mutex -Text "Quota exceeded, skip and try again on next run" -Type "Warning"
                                    Update-JobStatus -JobId $j.Id -Status ([JobStatus]::Queued) -WorkerName $VMName -SchedulerLog $script:Log -access_token_sql $access_token_sql
                                    continue # Skip this job and continue with the next one
                                } else {
                                    throw $_
                                }
                                
                            }
                            
                        }
                        
                        if($j.OperatingSystem -eq 0){

                            if(Get-AzVMADDomainExtension -Name "$VMName-DomainJoin" -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] -VMName $VMName -ErrorAction SilentlyContinue){
                                Write-Log -JobId $j.Id -Mutex $Mutex -Text "Domain Join extension already exists, continue to next extensions"
                            } else {
                                $DjCredential = New-Object System.Management.Automation.PSCredential ("$($Settings["SC_DOMAIN_FQDN"])\$($Settings["AdminUsername"])", $Settings["AdminDcPassword"]);
                                
                                $OU = 'OU=WorkerOU,DC=' + $Settings["SC_DOMAIN_FQDN"].Replace('.',',DC=')
                                Write-Log -JobId $j.Id -Mutex $Mutex -Text "Add domain join extension to join to '$OU'"
                                $r = Set-AzVMADDomainExtension `
                                -Name "$VMName-DomainJoin" `
                                -VMName $VMName `
                                -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] `
                                -DomainName $Settings["SC_DOMAIN_FQDN"] `
                                -Credential $DjCredential `
                                -JoinOption 0x00000003 `
                                -OUPath $OU `
                                -Restart -NoWait -Verbose
                                Write-Log -JobId $j.Id -Mutex $Mutex -Text "Add domain join extension result '$($r.StatusCode)'"
                            }
                        }
                        if($j.OperatingSystem -eq 0){
                            if(Get-AzVMExtension -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] -VMName $VMName -Name "ShieldChecker" -ErrorAction SilentlyContinue){
                                Write-Log -JobId $j.Id -Mutex $Mutex -Text "ShieldChecker (MDE Enrollment) extension already exists, continue"
                            } else {
                                Write-Log -JobId $j.Id -Mutex $Mutex -Text "Add ShieldChecker extension for MDE Enrollment Windows"
                                # Add MDE Extension
                                $fileUri = @("https://$($Settings["WEBSITE_HOSTNAME"])/api/Scripts?os=$($j.OperatingSystem)")
                                $ScriptSettings = @{"fileUris" = $fileUri};
                                $protectedSettings = @{"commandToExecute" = "cmd.exe /C rename Scripts Scripts.cmd & Scripts.cmd"};
                                

                                #run command
                                $r = Set-AzVMExtension -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] `
                                    -Location $Settings["SC_AZ_LOCATION"] `
                                    -VMName $VMName `
                                    -Name "ShieldChecker" `
                                    -Publisher "Microsoft.Compute" `
                                    -ExtensionType "CustomScriptExtension" `
                                    -TypeHandlerVersion "1.10" `
                                    -Settings $ScriptSettings `
                                    -ProtectedSettings $protectedSettings `
                                    -NoWait;
                                Write-Log -JobId $j.Id -Mutex $Mutex -Text "Add MDE Enrollment extension result '$($r.StatusCode)'"
        
                            }
                        } else {
                            if (Get-AzVMExtension -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] -VMName $VMName -Name "ShieldChecker" -ErrorAction SilentlyContinue) {
                                Write-Log -JobId $j.Id -Mutex $Mutex -Text "ShieldChecker (MDE Enrollment) extension already exists, continue"
                            } else {
                                Write-Log -JobId $j.Id -Mutex $Mutex -Text "Add ShieldChecker extension for MDE Enrollment and Powershell Linux"
                                # Add MDE Extension
                                $fileUri = @("https://$($Settings["WEBSITE_HOSTNAME"])/api/Scripts?os=$($j.OperatingSystem)",
                                "https://$($Settings["SC_STORAGE_DC_DSC"]).blob.core.windows.net/genericcontent/InstallPwsLinux.sh",
                                "https://$($Settings["SC_STORAGE_DC_DSC"]).blob.core.windows.net/genericcontent/InstallMdeLinux.sh",
                                "https://$($Settings["SC_STORAGE_DC_DSC"]).blob.core.windows.net/genericcontent/InstallXRdp.sh")
                                $ScriptSettings = @{"fileUris" = $fileUri}
                                $protectedSettings = @{"commandToExecute" = "mv Scripts config.py && chmod +x InstallPwsLinux.sh && chmod +x InstallXRdp.sh && chmod +x InstallMdeLinux.sh && chmod +x config.py && sudo ./InstallMdeLinux.sh --install --onboard ./config.py --channel prod --min_req --passive-mode && sudo ./InstallPwsLinux.sh && sudo ./InstallXRdp.sh"}

                                # Run command for Linux
                                $r = Set-AzVMExtension -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] `
                                    -Location $Settings["SC_AZ_LOCATION"] `
                                    -VMName $VMName `
                                    -Name "ShieldChecker" `
                                    -Publisher "Microsoft.Azure.Extensions" `
                                    -ExtensionType "CustomScript" `
                                    -TypeHandlerVersion "2.0" `
                                    -Settings $ScriptSettings `
                                    -ProtectedSettings $protectedSettings `
                                    -NoWait;

                                Write-Log -JobId $j.Id -Mutex $Mutex -Text "Add MDE Enrollment extension result '$($r.StatusCode)'"
                            }
                        }
                        
                        # Update Job Status
                        Update-JobStatus -JobId $j.Id -Status ([JobStatus]::WaitingForMDE) -WorkerName $VMName -WorkerIP $($NIC.IpConfigurations[0].PrivateIpAddress) -WorkerStart $true -SchedulerLog $script:Log -access_token_sql $access_token_sql
 
                    } catch {
                        Write-Log -JobId $j.Id -Mutex $Mutex -Text "Error processing job: $_" -Type "Error"
                        Remove-Worker
                        # Update Job Status
                        Update-JobStatus -JobId $j.Id -Status ([JobStatus]::Error) -SchedulerLog $script:Log -WorkerEnd $true -access_token_sql $access_token_sql
                        
                    }
                    
                }
                "WaitingForMDE" {
                    Write-Host "Job $($j.Id) is waiting for MDE";
                    try{
                        Write-Log -JobId $j.Id -Mutex $Mutex -Text "Job $($j.Id) is waiting for MDE, checking for machine '$($j.WorkerName)'"
                        
                        # Check if object is in mde
                        $machineId = Get-MdeMachine -MachineName $j.WorkerName -access_token_mde $access_token_mde
                        if($machineId){
                            Write-Log -JobId $j.Id -Mutex $Mutex -Text "MDE Enrollment is done with MachineId '$machineId'"
                            Write-Log -JobId $j.Id -Mutex $Mutex -Text "Tag device with ShieldChecker in MDE"
                            $resultMdeTagging = Set-MdeMachineTag -MachineId $machineId -access_token_mde $access_token_mde
                            Write-Log -JobId $j.Id -Mutex $Mutex -Text "Shieldchecker Tag assigned to device with ID '$($resultMdeTagging.id)' in MDE"
                            
                            # Add ShieldChecker Test Script
                            if($j.OperatingSystem -eq 0){
                                Write-Log -JobId $j.Id -Mutex $Mutex -Text "Prepare ShieldChecker Test Script Windows"
                                $fileUri = @("https://$($Settings["SC_STORAGE_DC_DSC"]).blob.core.windows.net/executor/WScExecutor.exe",
                                "https://$($Settings["SC_STORAGE_DC_DSC"]).blob.core.windows.net/executor/appsettings.json")
                                $ScriptSettings = @{"fileUris" = $fileUri};
                                $protectedSettings = @{"commandToExecute" = 'WScExecutor.exe'};

                                #run command
                                $r = Set-AzVMExtension `
                                    -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] `
                                    -Location $Settings["SC_AZ_LOCATION"] `
                                    -VMName $j.WorkerName `
                                    -Name "ShieldChecker" `
                                    -Publisher "Microsoft.Compute" `
                                    -ExtensionType "CustomScriptExtension" `
                                    -TypeHandlerVersion "1.10" `
                                    -Settings $ScriptSettings `
                                    -ProtectedSettings $protectedSettings `
                                    -ForceRerun "1.1" `
                                    -NoWait;
                                Write-Log -JobId $j.Id -Mutex $Mutex -Text "Added Testscript Windows extension result '$($r.StatusCode)'"
                            } else {
                                Write-Log -JobId $j.Id -Mutex $Mutex -Text "Prepare ShieldChecker Test Script Linux"
                                $fileUri = @(
                                "https://$($Settings["SC_STORAGE_DC_DSC"]).blob.core.windows.net/executor/LScExecutor",
                                "https://$($Settings["SC_STORAGE_DC_DSC"]).blob.core.windows.net/executor/appsettings.json")
                                $ScriptSettings = @{"fileUris" = $fileUri}
                                $protectedSettings = @{"commandToExecute" = "chmod +x LScExecutor && sudo ./LScExecutor"}

                                # Run command for Linux
                                $r = Set-AzVMExtension -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] `
                                    -Location $Settings["SC_AZ_LOCATION"] `
                                    -VMName $j.WorkerName `
                                    -Name "ShieldChecker" `
                                    -Publisher "Microsoft.Azure.Extensions" `
                                    -ExtensionType "CustomScript" `
                                    -TypeHandlerVersion "2.0" `
                                    -Settings $ScriptSettings `
                                    -ProtectedSettings $protectedSettings `
                                    -ForceRerun "1.1" `
                                    -NoWait;
                                Write-Log -JobId $j.Id -Mutex $Mutex -Text "Added Testscript Linux extension result '$($r.StatusCode)'"
                            }
                            # Update Job Status
                            Update-JobStatus -JobId $j.Id -Status ([JobStatus]::WaitingForDetection) -SchedulerLog $script:Log -DefenderMachineId $machineId -access_token_sql $access_token_sql

                        } else {
                            if([datetime]($j.WorkerStart) -lt ([DateTime]::UtcNow).AddMinutes(-1 * $Settings["JobTimeout"])){
                                Write-Log -JobId $j.Id -Mutex $Mutex -Text "Job $($j.Id) is waiting for mde enrollment, but time is over $($Settings["JobTimeout"]) Minutes"
                                if($Settings["JobReview"] -eq 1){
                                    Write-Log -JobId $j.Id -Mutex $Mutex -Text "Assigning Public IP to VM"
                                    $pip= Enable-PublicAccess
                            
                                    Write-Log -JobId $j.Id -Mutex $Mutex -Text "Set Pending Review"
                                    # Update Job Status
                                    Update-JobStatus -JobId $j.Id -Status ([JobStatus]::ReviewPending) -Result ([JobResult]::Undetermined) -WorkerRemoteIP $pip.IpAddress -SchedulerLog $script:Log -access_token_sql $access_token_sql
                                } else {
                                    Write-Log -JobId $j.Id -Mutex $Mutex -Text "Review is not enabled, set job to Completed with failed detection"
                                    Remove-Worker
                                    Write-Log -JobId $j.Id -Mutex $Mutex -Text "Cleanup VM"
                                    # Update Job Status
                                    Update-JobStatus -JobId $j.Id -Status ([JobStatus]::Error) -Result ([JobResult]::Failed) -SchedulerLog $script:Log -access_token_sql $access_token_sql
                                }
                            } else {
                                Write-Log -JobId $j.Id -Mutex $Mutex -Text "MDE Enrollment is not done"
                                # Update Job Status
                                Update-JobStatus -JobId $j.Id -Status ([JobStatus]::WaitingForMDE) -SchedulerLog $script:Log -access_token_sql $access_token_sql
                            }
                            
                        }
                        
                    } catch {
                        Write-Log -JobId $j.Id -Mutex $Mutex -Text "Error processing job: $_" -Type "Error"
                        Remove-Worker
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
                                Write-Log -JobId $j.Id -Mutex $Mutex -Text "Assigning Public IP to VM"
                                $pip = Enable-PublicAccess
                                Write-Log -JobId $j.Id -Mutex $Mutex -Text "Set Pending Review"
                                # Update Job Status
                                Update-JobStatus -JobId $j.Id -Status ([JobStatus]::ReviewPending) -Result ([JobResult]::Failed) -WorkerRemoteIP $pip.IpAddress -SchedulerLog $script:Log -access_token_sql $access_token_sql
                            } else {
                                Write-Log -JobId $j.Id -Mutex $Mutex -Text "Review is not enabled, set job to Completed with failed detection"
                                Remove-Worker
                                Write-Log -JobId $j.Id -Mutex $Mutex -Text "Cleanup VM"
                                # Update Job Status
                                Update-JobStatus -JobId $j.Id -Status ([JobStatus]::Completed) -Result ([JobResult]::Failed) -SchedulerLog $script:Log -access_token_sql $access_token_sql
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
                                Write-Log -JobId $j.Id -Mutex $Mutex -Text "Cleanup VM"
                                Remove-Worker
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
                        Remove-Worker
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
                        Remove-Worker
                        # Update Job Status
                        Update-JobStatus -JobId $j.Id -Status ([JobStatus]::Completed) -SchedulerLog $script:Log -WorkerEnd $true -access_token_sql $access_token_sql
                    } catch {
                        Write-Log -JobId $j.Id -Mutex $Mutex -Text "Error processing job: $_" -Type "Error"
                        Remove-Worker
                        # Update Job Status
                        Update-JobStatus -JobId $j.Id -Status ([JobStatus]::Error) -SchedulerLog $script:Log -WorkerEnd $true -access_token_sql $access_token_sql
                    }
                }
                "Completed" {
                    Write-Host "Job $($j.Id) completed";
                }
                "Canceled" {
                    Write-Host "Job $($j.Id) was canceled";
                    Write-Log -JobId $j.Id -Mutex $Mutex -Text "Job $($j.Id) is canceled"
                    Write-Log -JobId $j.Id -Mutex $Mutex -Text "Cleanup VM"
                    Remove-Worker
                    # Update Job Status
                    Update-JobStatus -JobId $j.Id -Status ([JobStatus]::Completed) -SchedulerLog $script:Log -WorkerEnd $true -access_token_sql $access_token_sql
                }
                default {
                    Write-Host "Unknown status $($j.Status)";
                }
            }
        }
        } else {
            Write-Host "Another worker is already processing jobs in second check"
        }
    } else {
        Write-Host "Another worker is already processing jobs"
    }
} catch {
    Write-Host "Error processing jobs: $_"
} finally {
    Invoke-ReleaseMutex
}

#end region process jobs
