[CmdletBinding()]
param()

Trace-VstsEnteringInvocation $MyInvocation

# Get inputs for the task
$clientId = Get-VstsInput -Name clientId -Require
$clientSecret = Get-VstsInput -Name clientSecret -Require
$tenantId = Get-VstsInput -Name tenantId -Require
$productExternalId = Get-VstsInput -Name productExternalId -Require
$targetType = Get-VstsInput -Name targetType -Require

$configureSchema = "https://product-ingestion.azureedge.net/schema/configure/2022-03-01-preview2"

# Import helper functions
. "../common/product_ingestion_helper.ps1"

if ($targetType -eq "")
{
    Write-VstsTaskError -Message  "Target type is required. Please provide one of the following values: preview, live."
    Exit 1
}

if ($targetType -ne "preview" -and $targetType -ne "live")
{
    Write-VstsTaskError -Message  "Invalid target type provided. Please provide one of the following values: preview, live."
    Exit 1
}

try
{
    Write-Output "Installing and logging into Azure CLI."
    InitializeAzCLI -clientId $clientId -clientSecret $clientSecret -tenantId $tenantId

    Write-Output "Checking for existing product with external ID: $productExternalId"
    $productDurableId = GetProductDurableId -productExternalId $productExternalId
    if ($productDurableId -eq "")
    {
        throw "Unable to publish to $targetType. Product with external ID $productExternalId not found."
    }
    else
    {
        Write-Output "Product $productExternalId found: $productDurableId. Publishing to $targetType."
        Publish -configureSchema $configureSchema -productDurableId $productDurableId -targetType $targetType
    }

    Write-VstsSetResult -Result "Succeeded" -AsOutput
}
catch
{
    Write-VstsTaskError -Message "There was an issue publishing your product to preview: $($_.Exception.Message)"
    Exit 1
}
finally
{
    Trace-VstsLeavingInvocation $MyInvocation
}

