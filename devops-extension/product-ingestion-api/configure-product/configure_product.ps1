[CmdletBinding()]
param()

Trace-VstsEnteringInvocation $MyInvocation

# Get inputs for the task
$clientId = Get-VstsInput -Name clientId -Require
$clientSecret = Get-VstsInput -Name clientSecret -Require
$tenantId = Get-VstsInput -Name tenantId -Require
$productConfigurationFile = Get-VstsInput -Name productConfigurationFile -Require

$test1 = ls
Write-Host $test1
$test2 = ls ../
Write-Host $test2
$test3 = ls ../../
Write-Host $test3
$test4 = ls ../../
Write-Host $test4

# Import helper functions
. "../common/product_ingestion_helper.ps1"

if (Test-Path -Path $productConfigurationFile)
{
    Write-Output "Product configuration file found. Using it."
}
else
{
    $errorMesage = "Product configuration file not found. Please specify the path to the product configuration file."
    Write-VstsTaskError -Message  $errorMesage
    throw $errorMesage
}

try
{
    Write-Output "Installing and logging into Azure CLI."
    InitializeAzCLI -clientId $clientId -clientSecret $clientSecret -tenantId $tenantId

    $configuration = Get-Content $productConfigurationFile -Raw | ConvertFrom-Json
    $externalId = $configuration.product.identity.externalId

    Write-Output "Checking for existing product with external ID: $externalId"
    $productDurableId = GetProductDurableId -productExternalId $externalId
    if ($productDurableId -eq "")
    {
        Write-Output "Creating new product: $externalId"
        $productDurableId = CreateProduct -configureSchema $configuration.'$schema' -productConfiguration $configuration.product
        Write-Output "Product $externalId has ID $productDurableId"

        # Update product details
        UpdateProduct -configureSchema $configuration.'$schema' -productDurableId $productDurableId -productResources $configuration.product.resources
        Write-Output "Product $externalId updated."

        foreach ($plan in $configuration.plans)
        {
            $planExternalId = $plan.identity.externalId
            Write-Output "Creating new plan: $planExternalId"
            $planDurableId = CreatePlan -configureSchema $configuration.'$schema' -productDurableId $productDurableId -planConfiguration $plan
            Write-Output "Plan $planExternalId has ID $planDurableId"

            # Update plan details
            UpdatePlan -configureSchema $configuration.'$schema' -productDurableId $productDurableId -planDurableId $planDurableId -planResources $plan.resources
            Write-Output "Plan $planExternalId updated."
        }
    }
    else
    {
        Write-Output "Product $externalId already exists. Updating product and plan details."

        # Update product details
        UpdateProduct -configureSchema $configuration.'$schema' -productDurableId $productDurableId -productResources $configuration.product.resources
        Write-Output "Product $externalId updated."

        foreach ($plan in $configuration.plans)
        {
            $planExternalId = $plan.identity.externalId
            $planDurableId = GetPlanDurableId -productDurableId $productDurableId -planExternalId $planExternalId
            if ($planDurableId -eq "")
            {
                Write-Output "Creating new plan: $planExternalId"
                $planDurableId = CreatePlan -configureSchema $configuration.'$schema' -productDurableId $productDurableId -planConfiguration $plan
                Write-Output "Plan $planExternalId has ID $planDurableId"
            }

            # Update plan details
            Write-Output "Updating details for plan $planExternalId."
            UpdatePlan -configureSchema $configuration.'$schema' -productDurableId $productDurableId -planDurableId $planDurableId -planResources $plan.resources
            Write-Output "Plan $planExternalId updated."
        }
    }

    Write-Output "Product & plans have been successfully configured."
    Write-VstsSetResult -Result "Succeeded" -AsOutput
}
catch
{
    Write-VstsTaskError -Message "There was an issue configuring your product: $($_.Exception.Message)"
    Exit 1
}
finally {
    Trace-VstsLeavingInvocation $MyInvocation
}
