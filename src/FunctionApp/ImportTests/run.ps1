param($Request, $TriggerMetadata)

enum ExecutorSystemType
{
    Worker
    DomainController
}
enum ExecutorUserType
{
    System
    local_admin
    domain_admin
    domain_user
}




function Update-Test {
    param (
        $atomic,
        $technique,
        [int]$os,
        $Settings, 
        $access_token
    )

    $testscript = '
if(-not (Get-PSRepository -Name "PSGallery")){
    Register-PSRepository -Default
}
try{
    $InstalledNuGet = Get-PackageProvider -Name NuGet -ForceBootstrap -ErrorAction SilentlyContinue
    if($null -eq $InstalledNuGet -or $InstalledNuGet.Version -le 2.8.5.201){
        Write-Host "Installing NuGet package provider"
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
    } else {
        Write-Host "NuGet package provider already installed"
    }
} catch {
    Write-Error "Unable to install NuGet package provider. Please check your PowerShell version and try again."
}

Install-Module -Name powershell-yaml -Force
IEX (IWR "https://raw.githubusercontent.com/redcanaryco/invoke-atomicredteam/master/install-atomicredteam.ps1" -UseBasicParsing);

Install-AtomicRedTeam -getAtomics -noPayloads -Force

# Get Prereqs for test
Invoke-AtomicTest '+$($technique.attack_technique)+' -TestGuids '+$($atomic.auto_generated_guid)+' -GetPrereqs
# Invoke
Invoke-AtomicTest '+$($technique.attack_technique)+' -TestGuids '+$($atomic.auto_generated_guid)+'
# Sleep then cleanup
Start-Sleep 3
Invoke-AtomicTest  '+$($technique.attack_technique)+' -TestGuids '+$($atomic.auto_generated_guid)+' -Cleanup
'

    Write-Host "Processing $($technique.attack_technique) - $($atomic.name)"
    # Get Adjustment if there is any
    $adjustment = $AtomicRedTeamAdjustments | Where-Object { $_.ID -eq $atomic.auto_generated_guid }
    $ExpectedAlerts = "Unknown"
    if(![String]::IsNullOrWhiteSpace($adjustment.ExpectedAlerts)){
        $ExpectedAlerts = $adjustment.ExpectedAlerts
    }
    $ExecutorSystemType = [ExecutorSystemType]::Worker
    if($adjustment.'Run On DC' -eq $true){
        $ExecutorSystemType = [ExecutorSystemType]::DomainController
    }
    $ExecutorUserType = [ExecutorUserType]::System
    if($adjustment.'Run as Domain Admin' -eq $true){
        $ExecutorUserType = [ExecutorUserType]::domain_admin
    }
    $ScriptPrerequisites = ""
    if($adjustment.'AD RSAT' -eq $true){
        $ScriptPrerequisites = 
@'
# Get the list of RSAT capabilities
$RSATCapabilities = Get-WindowsCapability -Name RSAT* -Online | Where-Object { $_.Name.StartsWith("Rsat.ActiveDirectory") -or $_.Name.StartsWith("Rsat.CertificateServices")  -or $_.Name.StartsWith("Rsat.Dns")  -or $_.Name.StartsWith("Rsat.DHCP")  -or $_.Name.StartsWith("Rsat.GroupPolicy") }

# Loop through each capability and install it
foreach ($capability in $RSATCapabilities) {
    $Name = $capability.Name
    Write-Host "Install: $($capability.Name)"
    Add-WindowsCapability -Online -Name $capability.Name
}
'@
    }
    if($adjustment.'Require IIS' -eq $true){
        $ScriptPrerequisites = 
@'
# Get the list of RSAT capabilities
$IISCapabilities = Get-WindowsOptionalFeature -Online | Where-Object FeatureName -like "IIS*"

# Loop through each capability and install it
foreach ($capability in $IISCapabilities) {
    Write-Host "Install: $($capability.FeatureName)"
    Enable-WindowsOptionalFeature -Online -NoRestart -FeatureName $capability.FeatureName
}
'@
    }
    # Check if import should be done
    if([String]::IsNullOrWhiteSpace($adjustment.'Do not import reason')){     
    
        $Query = @"
IF NOT EXISTS (
                        SELECT * 
                        FROM [dbo].[TestDefinition] AS u 
                        WHERE u.[MitreTechnique] = '$($technique.attack_technique)' 
                        AND u.[Description] LIKE '%$($atomic.auto_generated_guid)%'
                        AND u.[OperatingSystem] = $os
                    )
                    BEGIN
                        INSERT INTO [dbo].[TestDefinition] (
                            [Name],
                            [Description],
                            [Created],
                            [CreatedById],
                            [Modified],
                            [ModifiedById],
                            [ExpectedAlertTitle],
                            [ScriptPrerequisites],
                            [ScriptTest],
                            [ScriptCleanup],
                            [Enabled],
                            [ElevationRequired],
                            [OperatingSystem],
                            [MitreTechnique],
                            [ReadOnly],
                            [ExecutorSystemType],
                            [ExecutorUserType]
                        )
                        SELECT 
                            N'$($atomic.name.Replace("'", "''"))',
                            N'$($atomic.description.Replace("'", "''")) [$($atomic.auto_generated_guid)]',
                            GETUTCDATE(),
                            '{00000000-0000-0000-0000-000000000000}',
                            GETUTCDATE(),
                            '{00000000-0000-0000-0000-000000000000}',
                            N'$ExpectedAlerts',
                            N'$ScriptPrerequisites',
                            N'$testscript',
                            N'',
                            1,
                            1,
                            $os,
                            N'$($technique.attack_technique)',
                            1,
                            $([int]($ExecutorSystemType)),
                            $([int]($ExecutorUserType))
                    END
                    ELSE
                    BEGIN
                        UPDATE [dbo].[TestDefinition]
                        SET 
                            [ScriptPrerequisites] = N'$ScriptPrerequisites',
                            [ScriptTest] = N'$testscript',
                            [Modified] = GETUTCDATE(),
                            [Description] = N'$($atomic.description.Replace("'", "''")) [$($atomic.auto_generated_guid)]',
                            [Name] = N'$($atomic.name.Replace("'", "''"))',
                            [OperatingSystem] = $os,
                            [ExecutorSystemType] = $([int]($ExecutorSystemType)),
                            [ExecutorUserType] = $([int]($ExecutorUserType)),
                            [ElevationRequired] = 1,
                            [ExpectedAlertTitle] = N'$ExpectedAlerts'
                        WHERE [MitreTechnique] = '$($technique.attack_technique)'
                        AND [Description] LIKE '%$($atomic.auto_generated_guid)%'
                        AND [OperatingSystem] = $os
                    END
"@
        try{
        Invoke-Sqlcmd `
            -ServerInstance $Settings["SC_AZURE_SQL_SERVER_NAME"] `
            -Database $Settings["SC_AZURE_SQL_DATABASE_NAME"] `
            -AccessToken $access_token `
            -DisableVariables `
            -query $Query `
            -ErrorAction Stop 
        } catch {
            Write-Error "Unable to import $($technique.attack_technique) - $($atomic.name) to SQL Server. Please check the query and try again."
            Write-Host $Query
            Write-Error $_.Exception.Message -ErrorAction Stop
        }
    } else {
        Write-Host "Skipping $($technique.attack_technique) - $($atomic.name) because '$($adjustment.'Do not import reason')'"
    }
}

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


Write-Host "Connecting to Azure with Managed Identity"
Connect-AzAccount -Identity -AccountId $Settings["AZURE_CLIENT_ID"]
Write-Host "Connected to Azure"

Write-Host "Retrieving access token for SQL Server"    
$access_tokenSecStr  = (Get-AzAccessToken -ResourceUrl https://database.windows.net -AsSecureString).Token
$access_token = [System.Net.NetworkCredential]::new("", $access_tokenSecStr).Password
Write-Host "Access token retrieved"

Write-Host "Load AtomicRedTeamAdjustments from Storage Account"
$adjustmentUrl = "https://$($Settings["SC_STORAGE_DC_DSC"]).blob.core.windows.net/genericcontent/AtomicRedTeamAdjustments.json"
$adjustmentString = ""
try{
    $adjustmentString = Invoke-RestMethod -Uri $adjustmentUrl
    Write-Host "Loaded AtomicRedTeamAdjustments.json from Storage Account"

} catch {
    Write-Error "Unable to load '$adjustmentUrl' from Storage Account. Please check the file and try again."
    Write-Error $_.Exception.Message -ErrorAction Stop
}
Write-Host "Parse AtomicRedTeamAdjustments"
try{
    $AtomicRedTeamAdjustments = "[$($adjustmentString.Trim())]" | ConvertFrom-Json
    Write-Host "Parsed $($AtomicRedTeamAdjustments.Count) adjustments"
} catch {
    Write-Error "Unable to parse. Please check the file and try again."
    Write-Error $_.Exception.Message -ErrorAction Stop
}



if(-not (Get-PSRepository -Name "PSGallery")){
    Write-Host "Register PSGallery"
    Register-PSRepository -Default
}
if (-not (Get-InstalledModule -Name "powershell-yaml" -ErrorAction:SilentlyContinue)) {
    write-verbose "Installing powershell-yaml"
    Install-Module -Name powershell-yaml -Scope CurrentUser -Force -AllowPrerelease -RequiredVersion "0.4.8"
}
Write-Host "Install AtomicRedTeam"
Invoke-Expression (Invoke-WebRequest 'https://raw.githubusercontent.com/redcanaryco/invoke-atomicredteam/master/install-atomicredteam.ps1' -UseBasicParsing);
Install-AtomicRedTeam -getAtomics -noPayloads -Force -InstallPath "$($env:temp)\AtomicRedTeam"

Write-Host "Bugfix Load classes"
. C:\local\Temp\AtomicRedTeam\invoke-atomicredteam\Private\AtomicClassSchema.ps1

Write-Host "Get available techniques and tests"
$techniques = Get-ChildItem "$($env:temp)\AtomicRedTeam\atomics\*" -Recurse -Include T*.yaml 
Write-Host "Found $($techniques.count) yaml files"
$techniques = $techniques | Get-AtomicTechnique
Write-Host "Transformed to $($techniques.count) techniques"
$data = @{}
$windowsCount = 0
$linuxCount = 0
$data.Add("TechniquesCount", $techniques.count)
foreach ($technique in $techniques) {
    foreach ($atomic in $technique.atomic_tests) {
        # $technique.attack_technique -> T1222.002
        # $technique.display_name -> File and Directory Permissions Modification: FreeBSD, Linux and Mac File and Directory Permissions Modification
        # $atomic.auto_generated_guid -> 8e5c5532-1181-4c1d-bb79-b3a9f5dbd680
        # $atomic.description -> Creates a file with an alternate data stream and simulates executing that hidden code/file. Upon execution, "Stream Data Executed" will be displayed.
        # $atomic.name -> NTFS Alternate Data Stream Access
        # $atomic.supported_platforms -> {windows}
        Write-Verbose -Message 'Determining manual tests'

        if ($atomic.executor.name.Contains('manual')) {
            Write-Verbose -Message 'Unable to run manual tests'
        } else {
            if ($atomic.supported_platforms.contains("windows") -and ($atomic.executor -ne "manual")) {
                
                if (($atomic.executor.name -eq "sh" -or $atomic.executor.name -eq "bash")) {
                    Write-Verbose -Message "Unable to run sh or bash on windows"
                } else {
                    Update-Test -atomic $atomic -technique $technique -os 0 -Settings $Settings -access_token $access_token
                    $windowsCount++
                }
                
            }
            if ($atomic.supported_platforms.contains("linux") -and ($atomic.executor -ne "manual")) {     
                if ( $atomic.executor.name -eq "command_prompt") {
                    Write-Verbose -Message "Unable to run cmd.exe on windows"
                } else {
                    Update-Test -atomic $atomic -technique $technique -os 1 -Settings $Settings -access_token $access_token
                    $linuxCount++
                }
                
            } 
        }
    }
}
$data.Add("WindowsCount", $windowsCount)
$data.Add("LinuxCount", $linuxCount)
$data = $data | ConvertTo-Json -Depth 5
Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
    StatusCode = [System.Net.HttpStatusCode]::OK
    Body = $data
})