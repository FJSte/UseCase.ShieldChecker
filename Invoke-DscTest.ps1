Publish-AzVMDscConfiguration `
    -ConfigurationPath "$PSScriptRoot/src/VmDsc/DomainController/DeployDC.ps1"`
    -AdditionalPath "$PSScriptRoot/src/VmDsc/DomainController/additionaldata"`
    -OutputArchivePath "$($env:TEMP)/DeployDC.ps1.zip" -Force


$st = Get-AzStorageAccount -ResourceGroupName "rg-sc4" -Name "stsccudhrprd001"
Write-Host "Uploading DeployDC.ps1.zip to Azure Storage Account: $($st.Name)"
Set-AzStorageBlobContent -Container "windows-powershell-dsc"`
                    -File "$($env:TEMP)/DeployDC.ps1.zip" `
                    -Blob "DeployDC.ps1.zip"`
                    -Context $st.Context -Force

$password = ConvertTo-SecureString "C0nt0s0!" -AsPlainText -Force

$adminCredential = New-Object System.Management.Automation.PSCredential ("local_admin",$password );
$configurationArguments = @{ 
    adminCredential = $adminCredential
    domainFQDN = "shieldchecker.local"
    functionAppHostname = "fun-scc-udhr-westeurope-prd-001.azurewebsites.net"
}
Write-Host "Removing existing Deploy-DomainServices DSC extension if it exists"
Remove-AzVMDscExtension -ResourceGroupName "rg-sc4" -VMName "dc01" -Name "Deploy-DomainServices" -ErrorAction SilentlyContinue
Write-Host "Deploying Deploy-DomainServices DSC extension to VM dc01 in resource group rg-sc4"
Set-AzVMDscExtension `
    -ResourceGroupName "rg-sc4" `
    -Name "Deploy-DomainServices" `
    -VMName "dc01" `
    -ArchiveBlobName "DeployDC.ps1.zip" `
    -ArchiveStorageAccountName "stsccudhrprd001" `
    -ConfigurationArgument $configurationArguments `
    -ConfigurationName "Deploy-DomainServices" `
    -ArchiveContainerName "windows-powershell-dsc" `
    -Version "2.77" `
    -Location "westeurope" `
    -AutoUpdate -NoWait