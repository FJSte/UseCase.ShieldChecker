# Define a parameter named $Timer, typically used for a timer-based trigger in PowerShell automation
param($Timer)
# Output the current date and time to the console, indicating when the script is run
Write-Output "ProvisioningDC Timer trigger function executed at: $(Get-Date)"


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


$Mutex = [guid]::NewGuid().ToString()

function Invoke-CheckMutex {
    param(
    )
    $MutexDb = Invoke-Sqlcmd `
                    -ServerInstance $Settings["SC_AZURE_SQL_SERVER_NAME"] `
                    -Database $Settings["SC_AZURE_SQL_DATABASE_NAME"] `
                    -AccessToken $access_token_sql `
                    -query "SELECT * FROM [dbo].[SchedulerMutex] WHERE [SchedulerType] = 1 AND [Owner] != '$Mutex' AND [Start] > DATEADD(minute,-35,GETUTCDATE())"
    if($MutexDb.Count -eq 0) {
        Write-Host "No other worker is processing jobs, set mutex"
        Invoke-Sqlcmd `
                    -ServerInstance $Settings["SC_AZURE_SQL_SERVER_NAME"] `
                    -Database $Settings["SC_AZURE_SQL_DATABASE_NAME"] `
                    -AccessToken $access_token_sql `
                    -query "INSERT INTO [dbo].[SchedulerMutex] ([Owner],[Start],[SchedulerType]) VALUES ('$Mutex',GETUTCDATE(),1)"
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
                FROM [dbo].[SchedulerMutex] WHERE [SchedulerType] = 1 AND [Owner] = '$Mutex'"
    
}

function Write-DcLog {
    param(
        [string]$LogVarToExtend,
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
    $LogVarToExtend += "$Mutex - $JobId - $(Get-Date -Format o) - $Type - $Text`r`n"
    return $LogVarToExtend
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
$Settings.Add("SC_AZ_DC_SUBNET_ID", $env:SC_AZ_DC_SUBNET_ID)
$Settings.Add("WEBSITE_HOSTNAME", $env:WEBSITE_HOSTNAME)
$Settings.Add("SC_DOMAIN_FQDN", $env:SC_DOMAIN_FQDN)
$Settings.Add("SC_DEPLOY_ENVIRONMENT", $env:SC_DEPLOY_ENVIRONMENT)
$Settings.Add("SC_STORAGE_DC_DSC", $env:SC_STORAGE_DC_DSC)




Connect-AzAccount -Identity -AccountId $Settings["AZURE_CLIENT_ID"]
Update-AzConfig -DisplayBreakingChangeWarning $false 
$access_token_sql_SecStr  = (Get-AzAccessToken -ResourceUrl https://database.windows.net -AsSecureString).Token
$access_token_sql = [System.Net.NetworkCredential]::new("", $access_token_sql_SecStr).Password
Update-AzConfig -DisplayBreakingChangeWarning $true

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


#region process jobs
Write-Host "Try get Mutex"
try{
    if(Invoke-CheckMutex){
        Start-Sleep -Seconds (Get-Random -Minimum 0 -Maximum 5)
        if(Invoke-CheckMutex){
        
        
            $Log =$SystemStatusDb.DomainControllerLog
            $Log = Write-DcLog -LogVarToExtend $Log -JobId 0 -Mutex $Mutex -Text "Domain Controller Scheduler is in Status $($SystemStatusDb.DomainControllerStatus) '$([DomainControllerStatus].GetEnumName($SystemStatusDb.DomainControllerStatus))'";


            switch ([DomainControllerStatus].GetEnumName($SystemStatusDb.DomainControllerStatus)) {
                "NotStarted" {
                    try{
                        Write-Host "Domain Controller is not started";
                        $Log = Write-DcLog -LogVarToExtend $Log -JobId 0 -Mutex $Mutex -Text "Domain Controller creation has not started, start create VM"
                        $Log = Write-DcLog -LogVarToExtend $Log -JobId 0 -Mutex $Mutex -Text "Create VM with name '$($Settings["DomainControllerName"])'"

                        
                        $NIC = Get-AzNetworkInterface -Name "nic-$($Settings["DomainControllerName"])-01-$($Settings["SC_APP_NAME"])-$($Settings["SC_DEPLOY_ENVIRONMENT"])-001" -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] 
                        if($NIC){
                            $Log = Write-DcLog -LogVarToExtend $Log -JobId 0 -Mutex $Mutex -Text "VM NIC with name '$($NIC.Name)' already exists, continue to VM creation"
                            
                        } else {
                            $Log = Write-DcLog -LogVarToExtend $Log -JobId 0 -Mutex $Mutex -Text "Create NIC with name 'nic-$($Settings["DomainControllerName"])-01-$($Settings["SC_APP_NAME"])-$($Settings["SC_DEPLOY_ENVIRONMENT"])-001'"
                            $IPconfig = New-AzNetworkInterfaceIpConfig -Name "IPConfig1" -PrivateIpAddressVersion IPv4 -PrivateIpAddress "10.0.3.10" -SubnetId $Settings["SC_AZ_DC_SUBNET_ID"]
                            $NIC = New-AzNetworkInterface -Name "nic-$($Settings["DomainControllerName"])-01-$($Settings["SC_APP_NAME"])-$($Settings["SC_DEPLOY_ENVIRONMENT"])-001" -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] -Location $Settings["SC_AZ_LOCATION"] -IpConfiguration $IPconfig
                        }
                        if(Get-AzVM -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] -Name $Settings["DomainControllerName"] -ErrorAction SilentlyContinue){
                            $Log = Write-DcLog -LogVarToExtend $Log -JobId 0 -Mutex $Mutex -Text "VM with name '$($Settings["DomainControllerName"])' already exists, continue to extensions"
                            
                        } else {
                            $Log = Write-DcLog -LogVarToExtend $Log -JobId 0 -Mutex $Mutex -Text "Create VM with name '$($Settings["DomainControllerName"])'"

                            $Credential = New-Object System.Management.Automation.PSCredential ($Settings["AdminUsername"], $Settings["AdminWorkerPassword"]);
                            
                            $VirtualMachine = New-AzVMConfig -VMName $Settings["DomainControllerName"] -VMSize $Settings["DcVMSize"] -IdentityType None -EnableSecureBoot $true -EnableVtpm $true -Tags @{ShieldChecker="DC"}
                            $VirtualMachine = Set-AzVMOperatingSystem -VM $VirtualMachine -Windows -ComputerName $Settings["DomainControllerName"] -Credential $Credential -ProvisionVMAgent -EnableAutoUpdate
                            $VirtualMachine = Add-AzVMNetworkInterface -VM $VirtualMachine -Id $NIC.Id -DeleteOption Detach
                            $VirtualMachine = Set-AzVMSourceImage -VM $VirtualMachine -PublisherName ($Settings["DcVMImage"] -split(":"))[0] -Offer ($Settings["DcVMImage"] -split(":"))[1] -Skus ($Settings["DcVMImage"] -split(":"))[2] -Version ($Settings["DcVMImage"] -split(":"))[3]
                            $VirtualMachine = Set-AzVMBootDiagnostic -VM $VirtualMachine -Disable
                            
                            $r = New-AzVM `
                                -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] `
                                -Location $Settings["SC_AZ_LOCATION"] `
                                -VM $VirtualMachine `
                                -OSDiskDeleteOption Delete `
                                -Verbose 
                            
                            $Log = Write-DcLog -LogVarToExtend $Log -JobId 0 -Mutex $Mutex -Text "Create VM result '$($r.StatusCode)'"
                        }
                        
                        # Update Job Status
                        Update-JobStatus -Status ([DomainControllerStatus]::VMRequested) -SchedulerLog $Log -access_token_sql $access_token_sql
                    } catch {
                        $Log = Write-DcLog -LogVarToExtend $Log -JobId 0 -Mutex $Mutex -Text "Error creating VM: $_" -Type "Error"
                        Update-JobStatus -Status ([DomainControllerStatus]::Error) -SchedulerLog $Log -access_token_sql $access_token_sql
                    }
                }
                
                "VMRequested" {
                    try{
                        $Log = Write-DcLog -LogVarToExtend $Log -JobId 0 -Mutex $Mutex -Text "Domain Controller VM is created, start DC provisioning"
                        $adminCredential = New-Object System.Management.Automation.PSCredential ($Settings["AdminUsername"], $Settings["AdminDcPassword"]);
                        $configurationArguments = @{ 
                            adminCredential = $adminCredential
                            domainFQDN = $Settings["SC_DOMAIN_FQDN"]
                            functionAppHostname = $Settings["WEBSITE_HOSTNAME"]
                        }

                        Set-AzVMDscExtension `
                            -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] `
                            -Name "Deploy-DomainServices" `
                            -VMName $Settings["DomainControllerName"] `
                            -ArchiveBlobName "DeployDC.ps1.zip" `
                            -ArchiveStorageAccountName $Settings["SC_STORAGE_DC_DSC"] `
                            -ConfigurationArgument $configurationArguments `
                            -ConfigurationName "Deploy-DomainServices" `
                            -ArchiveContainerName "windows-powershell-dsc" `
                            -Version "2.77" `
                            -Location $Settings["SC_AZ_LOCATION"] `
                            -AutoUpdate `
                            -NoWait
                        $Log = Write-DcLog -LogVarToExtend $Log -JobId 0 -Mutex $Mutex -Text "DC provisioning requested"
                        # Update Job Status
                        Update-JobStatus -Status ([DomainControllerStatus]::DcProvisioningRequested) -SchedulerLog $Log -access_token_sql $access_token_sql
                    } catch {
                        $Log = Write-DcLog -LogVarToExtend $Log -JobId 0 -Mutex $Mutex -Text "Error provisioning DC: $_" -Type "Error"
                        Update-JobStatus -Status ([DomainControllerStatus]::Error) -SchedulerLog $Log -access_token_sql $access_token_sql
                    }
                }
                "DcProvisioningRequested" {
                    try{
                        Write-Host "Check if provisioning was successful";
                        $dcprov = Get-AzVMDscExtension -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] -VMName $Settings["DomainControllerName"] -Name "Deploy-DomainServices" -ErrorAction SilentlyContinue
                        if($dcprov.ProvisioningState -eq "Succeeded"){
                            if(Get-AzVMExtension -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] -VMName $Settings["DomainControllerName"] -Name "ShieldChecker" -ErrorAction SilentlyContinue){
                                $Log = Write-DcLog -LogVarToExtend $Log -JobId 0 -Mutex $Mutex -Text "ShieldChecker (MDE Enrollment) extension already exists, continue"
                            } else {
                                $Log = Write-DcLog -LogVarToExtend $Log -JobId 0 -Mutex $Mutex -Text "Add ShieldChecker extension for MDE Enrollment Windows"
                                # Add MDE Extension
                                $fileUri = @("https://$($Settings["WEBSITE_HOSTNAME"])/api/Scripts?os=0")
                                $ScriptSettings = @{"fileUris" = $fileUri};
                                $protectedSettings = @{"commandToExecute" = "cmd.exe /C rename Scripts Scripts.cmd & Scripts.cmd"};
                                

                                #run command
                                $r = Set-AzVMExtension -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] `
                                    -Location $Settings["SC_AZ_LOCATION"] `
                                    -VMName $Settings["DomainControllerName"] `
                                    -Name "ShieldChecker" `
                                    -Publisher "Microsoft.Compute" `
                                    -ExtensionType "CustomScriptExtension" `
                                    -TypeHandlerVersion "1.10" `
                                    -Settings $ScriptSettings `
                                    -ProtectedSettings $protectedSettings `
                                    -NoWait;
                                $Log = Write-DcLog -LogVarToExtend $Log -JobId 0 -Mutex $Mutex -Text "Add MDE Enrollment extension result '$($r.StatusCode)'"
                            }
                            $Log = Write-DcLog -LogVarToExtend $Log -JobId 0 -Mutex $Mutex -Text "Domain Controller provisioning is done" 
                            Update-JobStatus -Status ([DomainControllerStatus]::Initialized) -SchedulerLog $Log -access_token_sql $access_token_sql
                        } elseif($dcprov.ProvisioningState -eq "Provisioning failed" -or $dcprov.ProvisioningState -eq "Failed") {
                            $Log = Write-DcLog -LogVarToExtend $Log -JobId 0 -Mutex $Mutex -Text "DC provisioning failed: $_" -Type "Error"
                            Update-JobStatus -Status ([DomainControllerStatus]::Error) -SchedulerLog $Log -access_token_sql $access_token_sql
                        } else {
                            $Log = Write-DcLog -LogVarToExtend $Log -JobId 0 -Mutex $Mutex -Text "Domain Controller provisioning is not yet done" 
                            Update-JobStatus -Status ([DomainControllerStatus]::DcProvisioningRequested) -SchedulerLog $Log -access_token_sql $access_token_sql
                        }
                    } catch {
                        $Log = Write-DcLog -LogVarToExtend $Log -JobId 0 -Mutex $Mutex -Text "Error checking DC provisioning: $_" -Type "Error"
                        Update-JobStatus -Status ([DomainControllerStatus]::Error) -SchedulerLog $Log -access_token_sql $access_token_sql
                    }
                }
                "Initialized" { 
                    Write-Host "Domain Controller is initialized, do nothing.";
                }
                "ResetRequested" {
                    $Log = ""
                    $Log = Write-DcLog -LogVarToExtend $Log -JobId 0 -Mutex $Mutex -Text "Domain Controller reset requested"
                    $Log = Write-DcLog -LogVarToExtend $Log -JobId 0 -Mutex $Mutex -Text "Cleanup VM"
                    Stop-AzVM -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] -Name $Settings["DomainControllerName"] -Force -ErrorAction SilentlyContinue
                    $vm = Get-AzVM -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] -Name $Settings["DomainControllerName"] -ErrorAction SilentlyContinue
        
                    Remove-AzVM -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] -Name $Settings["DomainControllerName"] -Force -ForceDeletion $true -ErrorAction SilentlyContinue
                    if($null -ne $vm -and $null -ne $vm.StorageProfile.OsDisk.Name){
                        Write-Log -JobId $j.Id -Mutex $Mutex -Text "Remove Disk '$($vm.StorageProfile.OsDisk.Name)'"
                        Remove-AzDisk -ResourceGroupName $Settings["SC_AZ_RESSOURCEGROUP_NAME"] -DiskName $vm.StorageProfile.OsDisk.Name -Force -ErrorAction SilentlyContinue
                    }
                    Update-JobStatus -Status ([DomainControllerStatus]::NotStarted) -SchedulerLog $Log -access_token_sql $access_token_sql
                }

                "Error" {
                    Write-Host "Domain Controller is in error state, do nothing.";
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
