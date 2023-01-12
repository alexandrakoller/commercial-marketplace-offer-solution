[CmdletBinding()]
param()

Trace-VstsEnteringInvocation $MyInvocation

# Get inputs for the task
$clientId = Get-VstsInput -Name clientId -Require
$clientSecret = Get-VstsInput -Name clientSecret -Require
$tenantId = Get-VstsInput -Name tenantId -Require
$productConfigurationFile = Get-VstsInput -Name productConfigurationFile -Require
$command = Get-VstsInput -Name command -Require

Write-Host "Installing Azure CLI."
$ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'; rm .\AzureCLI.msi
Write-Host "Successfully installed Azure CLI."

Write-Host "Logging into Azure CLI using service principal."
$null = az login --service-principal -u $clientId -p $clientSecret --tenant $tenantId
Write-Host "Successfully logged into Azure CLI."

if ($command -eq "configure")
{
    ./configure_product.ps1 -productConfigurationFile $productConfigurationFile
}
elseif ($command -eq "publish")
{
    $productExternalId = Get-VstsInput -Name productExternalId -Require
    $targetType = Get-VstsInput -Name targetType -Require

    ./publish_product.ps1 -productExternalId $productExternalId -targetType $targetType
} else 
{
    Write-VstsTaskError -Message "Invalid command input."
    Exit 1
}

Write-VstsSetResult -Result "Succeeded" -AsOutput
Trace-VstsLeavingInvocation $MyInvocation