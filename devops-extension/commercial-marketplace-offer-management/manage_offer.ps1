[CmdletBinding()]
param()

Trace-VstsEnteringInvocation $MyInvocation

# Get inputs for the task
$clientId = Get-VstsInput -Name clientId -Require
$clientSecret = Get-VstsInput -Name clientSecret -Require
$tenantId = Get-VstsInput -Name tenantId -Require
$productConfigurationFile = Get-VstsInput -Name productConfigurationFile -Require
$command = Get-VstsInput -Name command -Require

$ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'; rm .\AzureCLI.msi

az login --service-principal -u $clientId -p $clientSecret --tenant $tenantId

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
    # Throw error
    Write-Error "Something went wrong"
}

Trace-VstsLeavingInvocation $MyInvocation