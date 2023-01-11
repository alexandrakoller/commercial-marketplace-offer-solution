[CmdletBinding()]
param()

Trace-VstsEnteringInvocation $MyInvocation

# Get inputs for the task
$productConfigurationFile = Get-VstsInput -Name productConfigurationFile -Require

./congigure_product.ps1 -productConfigurationFile $productConfigurationFile

Trace-VstsLeavingInvocation $MyInvocation