# Note PSScriptRoot will change when the extension executes
# your configuration function.  So, you need to save the value 
# when your configuration is loaded
$DscWorkingFolder = $PSScriptRoot

Configuration Deploy-DomainServices
{
    Param
    (
        [Parameter(Mandatory)]
        [String] $domainFQDN,

        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential] $adminCredential,

        [Parameter(Mandatory)]
        [String] $functionAppHostname
    )

    Import-DscResource -ModuleName 'PSDesiredStateConfiguration'
    Import-DscResource -ModuleName 'ActiveDirectoryDsc'
    Import-DscResource -ModuleName 'ComputerManagementDsc'
    Import-DscResource -ModuleName 'NetworkingDsc'

    # Create the NetBIOS name and domain credentials based on the domain FQDN
    [String] $domainNetBIOSName = (Get-NetBIOSName -DomainFQDN $domainFQDN)
    [System.Management.Automation.PSCredential] $domainCredential = New-Object System.Management.Automation.PSCredential ("${domainNetBIOSName}\$($adminCredential.UserName)", $adminCredential.Password)
    [System.Management.Automation.PSCredential] $domainUserCredential = New-Object System.Management.Automation.PSCredential ("${domainNetBIOSName}\Tester", $adminCredential.Password)
    $DN = 'DC=' + $domainFQDN.Replace('.',',DC=')
    $interface = Get-NetAdapter | Where-Object Name -Like "Ethernet*" | Select-Object -First 1
    $interfaceAlias = $($interface.Name)

    Node localhost
    {
        LocalConfigurationManager 
        {
            ConfigurationMode = 'ApplyOnly'
            RebootNodeIfNeeded = $true
        }

        WindowsFeature InstallDNS 
        { 
            Ensure = 'Present'
            Name = 'DNS'
        }

        WindowsFeature InstallDNSTools
        {
            Ensure = 'Present'
            Name = 'RSAT-DNS-Server'
            DependsOn = '[WindowsFeature]InstallDNS'
        }

        DnsServerAddress SetDNS
        { 
            Address = '127.0.0.1'
            InterfaceAlias = $interfaceAlias
            AddressFamily = 'IPv4'
            DependsOn = '[WindowsFeature]InstallDNS'
        }

        WindowsFeature InstallADDS
        {
            Ensure = 'Present'
            Name = 'AD-Domain-Services'
            DependsOn = '[WindowsFeature]InstallDNS'
        }

        WindowsFeature InstallADDSTools
        {
            Ensure = 'Present'
            Name = 'RSAT-ADDS-Tools'
            DependsOn = '[WindowsFeature]InstallADDS'
        }

        ADDomain CreateADForest
        {
            DomainName = $domainFQDN
            Credential = $domainCredential
            SafemodeAdministratorPassword = $domainCredential
            ForestMode = 'WinThreshold'
            DatabasePath = 'C:\NTDS'
            LogPath = 'C:\NTDS'
            SysvolPath = 'C:\SYSVOL'
            DependsOn = '[DnsServerAddress]SetDNS', '[WindowsFeature]InstallADDS'
        }

        PendingReboot RebootAfterCreatingADForest
        {
            Name = 'RebootAfterCreatingADForest'
            DependsOn = "[ADDomain]CreateADForest"
        }

        WaitForADDomain WaitForDomainController
        {
            DomainName = $domainFQDN
            WaitTimeout = 300
            RestartCount = 3
            Credential = $domainCredential
            WaitForValidCredentials = $true
            DependsOn = "[PendingReboot]RebootAfterCreatingADForest"
        }

        ADOrganizationalUnit CreateOU
        {
            Ensure = 'Present'
            Name = 'WorkerOU'
            Path = $DN
            Credential = $domainCredential
            DependsOn = "[WaitForADDomain]WaitForDomainController"
        }

        ADUser "$domainNetBIOSName\Tester"
        {
            Ensure     = 'Present'
            UserName   = 'Tester'
            Credential = $domainCredential
            Password   = $domainUserCredential
            DomainName = $domainFQDN
            UserPrincipalName = 'Tester@' + $domainFQDN
            PasswordNeverExpires = $true
            CannotChangePassword = $true
            DependsOn = "[WaitForADDomain]WaitForDomainController"
        }
        Script InstallGPO
        {
            SetScript = {
                $domain = Get-ADDomain
                $DN = $domain.DistinguishedName
                Import-Module GroupPolicy
                Import-GPO -Path "$($using:DscWorkingFolder)\additionaldata\GPO" -BackupGpoName "MonitorOnly" -TargetName "MonitorOnly" -CreateIfNeeded
                $Link = (Get-ADOrganizationalUnit -Identity "OU=WorkerOU,$DN" | Get-GPInheritance).GpoLinks | Where-Object { $_.DisplayName -eq "MonitorOnly" }
                if(-not $Link){
                    New-GPLink -Name "MonitorOnly" -Target "OU=WorkerOU,$DN" -LinkEnabled Yes -Enforced No -Order 1
                }
                $LinkDc = (Get-ADOrganizationalUnit -Identity "OU=Domain Controllers,$DN" | Get-GPInheritance).GpoLinks | Where-Object { $_.DisplayName -eq "MonitorOnly" }
                if(-not $LinkDc){
                    New-GPLink -Name "MonitorOnly" -Target "OU=Domain Controllers,$DN" -LinkEnabled Yes -Enforced No -Order 1
                }
            }
            TestScript = {
                $domain = Get-ADDomain
                $DN = $domain.DistinguishedName
                $gpo = Get-GPO -Name "MonitorOnly" -ErrorAction SilentlyContinue
                $Link = (Get-ADOrganizationalUnit -Identity "OU=WorkerOU,$DN" | Get-GPInheritance).GpoLinks | Where-Object { $_.DisplayName -eq "MonitorOnly" }
                
                if ($gpo -eq $null -or $Link -eq $null) {
                    return $false
                }
                return $true
            }
            GetScript = {
                $domain = Get-ADDomain
                $DN = $doman.DistinguishedName
                $Link = (Get-ADOrganizationalUnit -Identity "OU=WorkerOU,$DN" | Get-GPInheritance).GpoLinks | Where-Object { $_.DisplayName -eq "MonitorOnly" }
                
                $gpo = Get-GPO -Name "MonitorOnly"
                return $gpo.Id
            }
            DependsOn = "[ADOrganizationalUnit]CreateOU"
        }
        Script InstallMDI
        {
            SetScript = {
                try{
                    if((Get-ADOptionalFeature -Identity 'Recycle Bin Feature').EnabledScopes -eq $null){
                        Enable-ADOptionalFeature -Identity 'Recycle Bin Feature' -Scope ForestOrConfigurationSet -Target (Get-ADDomain).DNSRoot -Confirm:$false
                    }
                } catch {
                    Write-Verbose 'Recycle Bin Feature is already enabled'
                }
                if((Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)){
                    Write-Verbose 'PSGallery repository already exists'
                } else {
                    Write-Verbose 'Registering PSGallery repository'
                    Register-PSRepository -Default
                }
                
                Set-PsRepository -Name PSGallery -InstallationPolicy Trusted
                if($PSVersionTable.PSVersion -gt 7.4){
                    Import-Module -Name GroupPolicy -SkipEditionCheck
                }
                
                Install-Module DefenderForIdentity -Force -AllowClobber -Scope AllUsers -Repository PSGallery
                Test-MDIDSA -Identity "mdiSvc01" -Detailed
                if(-not (Test-MDIDSA -Identity "mdiSvc01")){
                    try{
                        New-MDIDSA -Identity "mdiSvc01" -GmsaGroupName "mdiSvcGroup01"
                    } catch {
                        Write-Verbose 'MDI Service Account already exists'
                    }
                } else {
                    Write-Verbose 'MDI Service Account already exists'
                }
                
                $Configurations = @(
                    "AdvancedAuditPolicyCAs",
                    "AdvancedAuditPolicyDCs",
                    "CAAuditing",
                    "ConfigurationContainerAuditing",
                    "EntraConnectAuditing",
                    "RemoteSAM",
                    "DomainObjectAuditing",
                    "NTLMAuditing",
                    "ProcessorPerformance"
                )
                Set-MDIConfiguration -Mode Domain -Configuration $Configurations -GpoNamePrefix "MDI" -Identity "mdiSvc01" -Force
                $domain = Get-ADDomain
                $DN = $domain.DistinguishedName
                $Link = (Get-ADOrganizationalUnit -Identity "OU=WorkerOU,$DN" | Get-GPInheritance).GpoLinks | Where-Object { $_.DisplayName -eq "MDI - Remote SAM Access" }
                if(-not $Link){
                    New-GPLink -Name "MDI - Remote SAM Access" -Target "OU=WorkerOU,$DN" -LinkEnabled Yes -Enforced No -Order 1
                }
                


            }
            GetScript =
            {
                Write-Verbose 'Checking for presence of MDI PS Module'
                try
                {
                    
                    if(Get-Module DefenderForIdentity){
                        $domain = Get-ADDomain
                        $DN = $domain.DistinguishedName
                        $Link = (Get-ADOrganizationalUnit -Identity "OU=WorkerOU,$DN" | Get-GPInheritance).GpoLinks | Where-Object { $_.DisplayName -eq "MDI - Remote SAM Access" }
                        $account = Test-MDIDSA -Identity "mdiSvc01"
                        if($account -and $link){
                            Write-Verbose 'MDI Prereq is installed'
                            return @{
                                'Result' = 'installed'
                            }
                        } else {
                            Write-Verbose 'MDI Prereq is NOT installed'
                            return @{
                                'Result' = 'missing'
                            }
                        }
                    } else  {
                        return @{
                            'Result' = 'missing'
                        }
                    }
                }
                catch [Microsoft.PowerShell.Commands.ServiceCommandException]
                {
                    return @{
                        'Result' = 'missing'
                    }
                }
            }

            TestScript =
            {
                $state = [scriptblock]::Create($GetScript).Invoke()
                if ($state['Result'] -eq 'missing')
                {
                    Write-Verbose 'MDI Prereq is NOT installed'
                    return $true   
                }
                Write-Verbose 'MDI Prereq is installed'
                return $false
            }                                                                                                                                                                   
            DependsOn = "[Script]InstallGPO"
            PsDscRunAsCredential = $domainCredential
        }
        Script PrepareScExecutor
        {
            SetScript = {
                if(-not (Test-Path "c:\TestEngine\ScExecutor")){
                    Write-Host "Creating directory c:\TestEngine\ScExecutor"
                    New-Item -Path c:\TestEngine -Name "ScExecutor" -ItemType Directory -Force 
                } else {
                    Write-Host "Directory c:\TestEngine\ScExecutor already exists"
                }
                if(Get-Service -Name "SCExecutorSvc" -ErrorAction SilentlyContinue){
                    Write-Host "Service SCExecutorSvc already exists, removing it"
                    Stop-Service -Name "SCExecutorSvc" -Force -ErrorAction SilentlyContinue
                    sc.exe delete SCExecutorSvc
                }
        
                Copy-Item -Path "$($using:DscWorkingFolder)\additionaldata\Executor\ScExecutorSvc.exe" -Destination "c:\TestEngine\ScExecutor\ScExecutorSvc.exe" -Force
                Write-Host "Copied ScExecutorSvc.exe to c:\TestEngine\ScExecutor\ScExecutorSvc.exe"
                '{
                "Logging": {
                    "LogLevel": {
                    "Default": "Information",
                    "Microsoft.Hosting.Lifetime": "Information"
                    }
                },
                "AzureFunctionUrl":  "'+$($using:functionAppHostname)+'"
                }' | Out-File -FilePath "c:\TestEngine\ScExecutor\appsettings.json" -Force
                
                if(Get-Service -Name "SCExecutorSvc" -ErrorAction SilentlyContinue){
                    Write-Host "Service SCExecutorSvc already exists, removing it"
                    Start-Service -Name "SCExecutorSvc" -ErrorAction SilentlyContinue
                } else {
                    Write-Host "Service SCExecutorSvc does not exist, creating it"

                    sc.exe create SCExecutorSvc binPath= "c:\TestEngine\ScExecutor\ScExecutorSvc.exe" DisplayName= "ShieldChecker Execution Service" start= auto
                    sc.exe description SCExecutorSvc "Checks for jobs which need to be executed on the domain controller."
                    sc.exe failure SCExecutorSvc reset=1 actions=restart/60000/restart/60000/restart/60000
                    Start-Service -Name "SCExecutorSvc" -ErrorAction SilentlyContinue
                }
                
            }
            GetScript =
            {
                Write-Verbose 'Checking for presence of ScExecutorScv files'
                try
                {
                    
                    if((Test-Path "c:\TestEngine\ScExecutor\appsettings.json") -and (Test-Path "c:\TestEngine\ScExecutor\ScExecutorSvc.exe") -and (Get-Service -Name "SCExecutorSvc" -ErrorAction SilentlyContinue)){
                        
                        Write-Verbose 'ScExecutor Files are installed'
                        return @{
                            'Result' = 'installed'
                        }
                    } else {
                        Write-Verbose 'ScExecutor Files are NOT installed'
                        return @{
                            'Result' = 'missing'
                        }
                    }
                    
                }
                catch [Microsoft.PowerShell.Commands.ServiceCommandException]
                {
                    return @{
                        'Result' = 'missing'
                    }
                }
            }

            TestScript =
            {
                $state = [scriptblock]::Create($GetScript).Invoke()
                if ($state['Result'] -eq 'missing')
                {
                    Write-Verbose 'ScExecutor Files are NOT installed'
                    return $true   
                }
                Write-Verbose 'ScExecutor Files are installed'
                return $false
            }                                                                                                                                                                   
            DependsOn = "[Script]InstallGPO"
        }
    }
}

function Get-NetBIOSName {
    [OutputType([string])]
    param(
        [string] $domainFQDN
    )

    if ($domainFQDN.Contains('.')) {
        $length = $domainFQDN.IndexOf('.')
        if ( $length -ge 16) {
            $length = 15
        }
        return $domainFQDN.Substring(0, $length)
    }
    else {
        if ($domainFQDN.Length -gt 15) {
            return $domainFQDN.Substring(0, 15)
        }
        else {
            return $domainFQDN
        }
    }
}