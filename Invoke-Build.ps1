#Requires -Version 7.0

# Defining important variables

Write-Host "Starting Build Process..." -ForegroundColor Green
Write-Host "Defining variables" -ForegroundColor Green
Write-Host "- Script Root Path $PSScriptRoot"
$reqModules = @("Az.Accounts","Az.Compute","PSDesiredStateConfiguration","ActiveDirectoryDsc","ComputerManagementDsc","NetworkingDsc","ImportExcel")
Write-Host "- Required Modules $($reqModules -join ", "))"

# Prepare Build Name

$BuildName = Get-Date -Format "yyyyMMdd-HHmmss"
Write-Host "Define Build  '$BuildName'"
# check Buildenvironment
Write-Host "Check Build Environment" -ForegroundColor Green
Write-Host "- Check dotnet SDK"
try{
    $DotNetVersion = dotnet.exe --version 
    if($DotNetVersion -gt "9.0.0"){
        Write-Host "  - Dotnet Version $DotNetVersion found"
    } else {
        Write-Host "  - Dotnet Version $DotNetVersion found. Please update to 9.0.0 or higher"  
        exit 990001
    }
} catch {
    Write-Host "  - Dotnet 9 SDK not found"
    exit 990002
}
Write-Host "- Check dotnet ef tool"
try{
    $DotNetEfVersion = dotnet-ef --version
    if($DotNetEfVersion -gt "9.0.0"){
        Write-Host "  - Dotnet EF Version $DotNetEfVersion found"
    } else {
        Write-Host "  - Dotnet EF Version $DotNetEfVersion found. Update to 9.0.0 or higher"  
        dotnet tool install --global dotnet-ef --version 9.*
    }
} catch {
    Write-Host "  - Install dotnet ef tool"
    dotnet tool install --global dotnet-ef --version 9.*
}
Write-Host "- Check existing NuGet sources"
$nugetSources = dotnet nuget list source
if(!(($nugetSources -join "").Contains("https://api.nuget.org/v3/index.json"))){
    Write-Host "  - Add nuget.org as source"
    dotnet nuget add source https://api.nuget.org/v3/index.json -n nuget.org
    Write-Host "  - nuget.org added as a NuGet source."
}
Write-Host "- Check required PowerShell modules"
Write-Host "  - Checking for NuGet provider in Powershell"
if(Get-PackageProvider -Name NuGet -ListAvailable){
    Write-Host "  - NuGet provider found"
} else {
    Write-Host "  - NuGet provider not found. Installing NuGet provider"
    Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Scope CurrentUser
}
$reqModules | ForEach-Object {
    if (-not (Get-Module -ListAvailable -Name $_)) {
        Write-Host "  - Installing module $_"
        Install-Module -Name $_ -Force -Scope CurrentUser -AllowClobber -ErrorAction Stop
    } else {
        Write-Host "  - Module $_ already installed"
        Import-Module -Name $_
    }
}

# Prepare Deploy folder structure
Write-Host "Preparing Deploy folder structure..." -ForegroundColor Green
New-Item -Path "$PSScriptRoot/Deploy" -Name $BuildName -ItemType Directory -Force | Out-Null
Write-Host "- Created Deploy folder: $PSScriptRoot/Deploy/$BuildName"
New-Item -Path "$PSScriptRoot/Deploy/$BuildName" -Name "step1" -ItemType Directory -Force | Out-Null
Write-Host "- Created step1 folder: $PSScriptRoot/Deploy/$BuildName/step1"
New-Item -Path "$PSScriptRoot/Deploy/$BuildName" -Name "step2" -ItemType Directory -Force | Out-Null
Write-Host "- Created step2 folder: $PSScriptRoot/Deploy/$BuildName/step2"
New-Item -Path "$PSScriptRoot/Deploy/$BuildName/step2" -Name "VmDsc" -ItemType Directory -Force | Out-Null
Write-Host "- Created step2/VmDsc folder: $PSScriptRoot/Deploy/$BuildName/step2/VmDsc"
New-Item -Path "$PSScriptRoot/Deploy/$BuildName/step2" -Name "GenericContent" -ItemType Directory -Force | Out-Null
Write-Host "- Created step2/GenericContent folder: $PSScriptRoot/Deploy/$BuildName/step2/GenericContent"

# Build Webapps
Write-Host "Building Webapp..." -ForegroundColor Green
Write-Host "- Restoring NuGet packages for the Webapp..."
dotnet restore "$PSScriptRoot\src\Webapp\ShieldChecker.WebApp\ShieldChecker.WebApp.csproj"
Write-Host "- Building the Webapp in Release configuration..."
dotnet build "$PSScriptRoot\src\Webapp\ShieldChecker.WebApp\ShieldChecker.WebApp.csproj" --configuration Release --no-restore
Write-Host "- Publishing the Webapp to Deploy folder..."
dotnet publish "$PSScriptRoot\src\Webapp\ShieldChecker.WebApp\ShieldChecker.WebApp.csproj" --no-build -c Release -o "$PSScriptRoot/Deploy/$BuildName/step2/Webapp" 
Write-Host "- Webapp published to: $PSScriptRoot/Deploy/$BuildName/step2/Webapp, creating ZIP file..."
Compress-Archive -Path "$PSScriptRoot/Deploy/$BuildName/step2/Webapp/*"  -DestinationPath "$PSScriptRoot/Deploy/$BuildName/step2/Webapp.zip" -Force
Write-Host "- Webapp ZIP file created at: $PSScriptRoot/Deploy/$BuildName/step2/Webapp.zip"
Remove-Item -Path "$PSScriptRoot/Deploy/$BuildName/step2/Webapp" -Recurse -Force
Write-Host "- Removed Webapp folder"

# Build Executor
Write-Host "Building Executor Service ..." -ForegroundColor Green
Write-Host "- Restoring NuGet packages for the Executor Service ..."
dotnet restore "$PSScriptRoot\src\Executor\ShieldChecker.Executor.Service\ShieldChecker.Executor.Service.csproj"
Write-Host "- Building the Windows Executor Service in Release configuration..."
dotnet publish "$PSScriptRoot\src\Executor\ShieldChecker.Executor.Service\ShieldChecker.Executor.Service.csproj" --self-contained --configuration Release --no-restore --runtime win-x64 -o "$PSScriptRoot/src/VmDsc/DomainController/additionaldata/Executor"
Write-Host "Building Executor Console ..." -ForegroundColor Green
Write-Host "- Restoring NuGet packages for the Executor Console ..."
dotnet restore "$PSScriptRoot\src\Executor\ShieldChecker.Executor.Console\ShieldChecker.Executor.Console.csproj"

Write-Host "- Building the Linux Executor Console in Release configuration..."
dotnet publish "$PSScriptRoot\src\Executor\ShieldChecker.Executor.Console\ShieldChecker.Executor.Console.csproj" --self-contained --configuration Release --no-restore --runtime linux-x64 -o "$PSScriptRoot/Deploy/$BuildName/step2/Executor/Linux"
Write-Host "- Building the Windows Executor Console in Release configuration..."
dotnet publish "$PSScriptRoot\src\Executor\ShieldChecker.Executor.Console\ShieldChecker.Executor.Console.csproj" --self-contained --configuration Release --no-restore --runtime win-x64 -o "$PSScriptRoot/Deploy/$BuildName/step2/Executor/Windows"


# Build SQL Scripts
Write-Host "- Generating SQL scripts..."
dotnet ef migrations script --project "$PSScriptRoot\src\Webapp\ShieldChecker.WebApp\ShieldChecker.WebApp.csproj" --idempotent --output "$PSScriptRoot/Deploy/$BuildName/step2/SqlScripts/sql-database.sql"
Write-Host "- SQL scripts generated at: $PSScriptRoot/Deploy/$BuildName/step2/SqlScripts/sql-database.sql"
#Write-Warning "- Fixing SQL Script can be removed as soon ef core 9.0.1 is out with the following fix: https://github.com/dotnet/efcore/issues/35132"
#$InitializeDatabase = Get-Content "$PSScriptRoot/Deploy/$BuildName/step2/SqlScripts/sql-database.sql" -Raw -ErrorAction Stop
#$InitializeDatabase = $InitializeDatabase -replace "END;",("END;"+[Environment]::NewLine+"GO"+[Environment]::NewLine)
#Set-Content -Path "$PSScriptRoot/Deploy/$BuildName/step2/SqlScripts/sql-database.sql" -Value $InitializeDatabase -Force
Write-Host "- Copy SQL initialization script to Deploy folder..."
Copy-item -Path "$PSScriptRoot/src/Webapp/ShieldChecker.WebApp/Models/Db/sql-initialization.sql" -Destination "$PSScriptRoot/Deploy/$BuildName/step2/SqlScripts/sql-initialization.sql" -Force

# Copy Generic Storage Account Content
Write-Host "Copy Generic Storage Account Content to Deploy folder" -ForegroundColor Green
Copy-Item -Path "$PSScriptRoot/src/Bicep/step2/GenericContent/*" -Destination "$PSScriptRoot/Deploy/$BuildName/step2/GenericContent" -Recurse -Force
Write-Host "- Generic Storage Account Content copied to: $PSScriptRoot/Deploy/$BuildName/step2/GenericContent"

# Build DSC 
Write-Host "Create Azure VM DSC configuration..." -ForegroundColor Green
Publish-AzVMDscConfiguration -ConfigurationPath "$PSScriptRoot/src/VmDsc/DomainController/DeployDC.ps1" -AdditionalPath "$PSScriptRoot/src/VmDsc/DomainController/additionaldata" -OutputArchivePath "$PSScriptRoot/Deploy/$BuildName/step2/VmDsc/DeployDC.ps1.zip"
Write-Host "- Azure VM DSC configuration published to: $PSScriptRoot/Deploy/$BuildName/step2/VmDsc/DeployDC.ps1.zip"

# Build bicep templates
Write-Host "Adding Bicep templates to Deploy folder" -ForegroundColor Green
Copy-item -Path "$PSScriptRoot/src/Bicep/*" -Destination "$PSScriptRoot/Deploy/$BuildName" -Recurse -Force

# Build Azure Function files
Write-Host "Adding Azure Function Files to Deploy folder" -ForegroundColor Green
Copy-item -Path "$PSScriptRoot/src/FunctionApp" -Destination "$PSScriptRoot/Deploy/$BuildName/step1" -Recurse -Force
Write-Host "- Azure Function files copied to: $PSScriptRoot/Deploy/$BuildName/step1"
Write-Host "- Import Atomic Adjustments from Excel file"
$adjustments = Import-Excel -Path "$PSScriptRoot/SupportiveContent/AtomicRedTeamAdjustments.xlsx" -WorksheetName "Atomic" 
$adjustmentString = ($adjustments | Select-Object -ExcludeProperty Description | ConvertTo-Json -Depth 1).Replace("'","").Replace("[","").Replace("]","")
Write-Host "- Adjustments replaced in ImportTests script"
Set-Content "$PSScriptRoot/Deploy/$BuildName/step2/GenericContent/AtomicRedTeamAdjustments.json" -Value $adjustmentString -Force

# Copy Deployment Script
Write-Host "Copy Deployment Script to Deploy folder" -ForegroundColor Green
Copy-item -Path "$PSScriptRoot/Invoke-Deploy.ps1" -Destination "$PSScriptRoot/Deploy/$BuildName/Invoke-Deploy.ps1" -Force
Copy-item -Path "$PSScriptRoot/Invoke-UpdateWebAppAndSql.ps1" -Destination "$PSScriptRoot/Deploy/$BuildName/Invoke-UpdateWebAppAndSql.ps1" -Force

# Copy Deployment Script
Write-Host "Generate Latest Version in Deploy folder" -ForegroundColor Green
Remove-Item -Path "$PSScriptRoot/Deploy/Latest/*" -Recurse -Force
Copy-item -Path "$PSScriptRoot/Deploy/$BuildName/*" -Destination "$PSScriptRoot/Deploy/Latest" -Recurse -Force
