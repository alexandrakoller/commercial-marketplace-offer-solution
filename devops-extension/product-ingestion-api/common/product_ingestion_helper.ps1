# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

#####################################################################################################
# This script contains helper methods used to configure a Commercial Marketplace offer using the    #
# Product Ingestion API. This script can be used to create a new offer or update an existing offer. #
#####################################################################################################
$baseUrl = "https://graph.microsoft.com/rp/product-ingestion"
$configureBaseUrl = "$baseUrl/configure"

function InitializeAzCLI {
    param (
        [String] $clientId,
        [String] $clientSecret,
        [String] $tenantId
    )
    $ProgressPreference = 'SilentlyContinue'; Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'; rm .\AzureCLI.msi

    $null = az login --service-principal -u $clientId -p $clientSecret --tenant $tenantId
}

function GetHeaders {
    $token = az account get-access-token --resource=https://graph.microsoft.com --query accessToken --output tsv
    $requestHeaders = @{Authorization="Bearer $token"}
    return $requestHeaders
}

function GetProductDurableId {
    param (
        [String] $productExternalId
    )

    $headers = GetHeaders
    $response = Invoke-WebRequest -Method GET -Headers $headers -Uri "$baseUrl/product?externalId=$productExternalId" -ContentType "application/json" -UseBasicParsing
    if ($response.StatusCode -eq 200)
    {
        $content = $response.Content | ConvertFrom-Json
        if ($content.value.length -gt 0)
        {
            return $content.value[0].id
        }
    }

    return ""
}

function GetPlanDurableId {
    param (
        [String] $productDurableId,
        [String] $planExternalId
    )

    $headers = GetHeaders
    $response = Invoke-WebRequest -Method GET -Headers $headers -Uri "$baseUrl/plan?product=$productDurableId&externalId=$planExternalId" -ContentType "application/json" -UseBasicParsing
    if ($response.StatusCode -eq 200)
    {
        $content = $response.Content | ConvertFrom-Json
        if ($content.value.length -gt 0)
        {
            return $content.value[0].id
        }
    }

    return ""
}

function GetProductListingDurableId {
    param (
        [String] $productDurableId
    )

    $headers = GetHeaders
    $response = Invoke-WebRequest -Method GET -Headers $headers -Uri "$baseUrl/resource-tree/$productDurableId" -ContentType "application/json" -UseBasicParsing
    if ($response.StatusCode -eq 200)
    {
        $content = $response.Content | ConvertFrom-Json
        foreach ($resource in $content.resources)
        {
            if ($resource.'$schema'.StartsWith("https://product-ingestion.azureedge.net/schema/listing/"))
            {
                return $resource.id
            }
        }
    }

    return ""
}

function GetConfigureJobStatus {
    param (
        [String] $jobId
    )

    $headers = GetHeaders
    $response = Invoke-WebRequest -Method GET -Headers $headers -Uri "$configureBaseUrl/$jobId/status" -ContentType "application/json" -UseBasicParsing
    return $response
}

function GetConfigureJobDetail {
    param (
        [String] $jobId
    )

    $headers = GetHeaders
    $response = Invoke-WebRequest -Method GET -Headers $headers -Uri "$configureBaseUrl/$jobId" -ContentType "application/json" -UseBasicParsing
    return $response
}

function WaitForJobComplete {
    param (
        [String] $jobId
    )

    $headers = GetHeaders
    $jobResult = ""
    $maxRetries = 5
    $retries = 0
    while ($retries -lt $maxRetries) {
        $response = GetConfigureJobStatus -jobId $jobId
        if ($response.StatusCode -eq 200)
        {
            $content = $response.Content | ConvertFrom-Json
            if ($content.jobStatus -eq "completed")
            {
                $jobResult = $content.jobResult
                break
            }

            $sleepSeconds = [System.Math]::Pow(2, $retries)
            Start-Sleep -Seconds $sleepSeconds
        }

        $retries++
    }

    return $jobResult
}

function CreateProduct {
    param (
        [String] $configureSchema,
        $productConfiguration
    )

    $body = @{
        "`$schema" = $configureSchema
        "resources" = @(
            @{
                "`$schema" = $productConfiguration.'$schema'
                "identity" = @{
                    "externalId" = $productConfiguration.identity.externalId
                }
                "type" = $productConfiguration.type
                "alias" = $productConfiguration.alias
            }
        )
    } | ConvertTo-Json -Depth 5

    $headers = GetHeaders
    $response = Invoke-WebRequest -Method POST -Headers $headers -Uri $configureBaseUrl -Body $body -ContentType "application/json" -UseBasicParsing
    if ($response.StatusCode -eq 202)
    {
        $content = $response.Content | ConvertFrom-Json
        $jobId = $content.jobId
        $jobResult = WaitForJobComplete -jobId $jobId

        if ($jobResult -eq "succeeded")
        {
            $response = GetConfigureJobDetail -jobId $jobId
            if ($response.StatusCode -eq 200)
            {
                $content = $response.Content | ConvertFrom-Json
                return $content.resources[0].id
            }
        }
        else
        {
            $response = GetConfigureJobStatus -jobId $jobId
            if ($response.StatusCode -eq 200)
            {
                $content = $response.Content | ConvertFrom-Json
                $errorCode = $content.errors[0].code
                $errorMessage = $content.errors[0].message

                throw "There was an issue creating the product. Code: $errorCode. Message: $errorMessage"
            }
        }
    }
    else
    {
        throw "There was an issue creating the product. Status code: $($response.StatusCode)"
    }
}

function CreatePlan {
    param (
        [String] $configureSchema,
        [String] $productDurableId,
        $planConfiguration
    )

    $body = @{
        "`$schema" = $configureSchema
        "resources" = @(
            @{
                "`$schema" = $planConfiguration.'$schema'
                "identity" = @{
                    "externalId" = $planConfiguration.identity.externalId
                }
                "alias" = $planConfiguration.alias
                "azureRegions" = $planConfiguration.azureRegions
                "product" = $productDurableId
            }
        )
    } | ConvertTo-Json -Depth 5

    $headers = GetHeaders
    $response = Invoke-WebRequest -Method POST -Headers $headers -Uri $configureBaseUrl -Body $body -ContentType "application/json" -UseBasicParsing
    if ($response.StatusCode -eq 202)
    {
        $content = $response.Content | ConvertFrom-Json
        $jobId = $content.jobId
        $jobResult = WaitForJobComplete -jobId $jobId

        if ($jobResult -eq "succeeded")
        {
            $response = GetConfigureJobDetail -jobId $jobId
            if ($response.StatusCode -eq 200)
            {
                $content = $response.Content | ConvertFrom-Json
                return $content.resources[0].id
            }
        }
        else
        {
            $response = GetConfigureJobStatus -jobId $jobId
            if ($response.StatusCode -eq 200)
            {
                $content = $response.Content | ConvertFrom-Json
                $errorCode = $content.errors[0].code
                $errorMessage = $content.errors[0].message

                throw "There was an issue creating the plan. Code: $errorCode. Message: $errorMessage"
            }
        }
    }
    else
    {
        throw "There was an issue creating the plan. Status code: $($response.StatusCode)"
    }
}

function PostConfigure {
    param (
        [String] $configureSchema,
        $resources
    )

    $body = @{
        "`$schema" = $configureSchema
        "resources" = $resources
    } | ConvertTo-Json -Depth 10

    $headers = GetHeaders
    $response = Invoke-WebRequest -Method POST -Headers $headers -Uri $configureBaseUrl -Body $body -ContentType "application/json" -UseBasicParsing
    if ($response.StatusCode -eq 202)
    {
        $content = $response.Content | ConvertFrom-Json
        $jobId = $content.jobId
        $jobResult = WaitForJobComplete -jobId $jobId

        if ($jobResult -ne "succeeded")
        {
            $response = GetConfigureJobStatus -jobId $jobId
            if ($response.StatusCode -eq 200)
            {
                $content = $response.Content | ConvertFrom-Json
                $errorCode = $content.errors[0].code
                $errorMessage = $content.errors[0].message

                throw "Code: $errorCode. Message: $errorMessage"
            }
        }
    }
    else
    {
        throw "Status code: $($response.StatusCode)"
    }
}

function UpdateProduct {
    param (
        [String] $configureSchema,
        [String] $productDurableId,
        $productResources
    )

    $productListingDurableId = GetProductListingDurableId -productDurableId $productDurableId

    foreach ($resource in $productResources)
    {
        $resource | Add-Member -Name "product" -value $productDurableId -MemberType NoteProperty

        if ($resource.'$schema'.StartsWith("https://product-ingestion.azureedge.net/schema/listing-asset/") -or $resource.'$schema'.StartsWith("https://product-ingestion.azureedge.net/schema/listing-trailer/"))
        {
            $resource | Add-Member -Name "listing" -value $productListingDurableId -MemberType NoteProperty
        }
    }

    PostConfigure -configureSchema $configureSchema -resources $productResources
}

function UpdatePlan {
    param (
        [String] $configureSchema,
        [String] $productDurableId,
        [String] $planDurableId,
        $planResources
    )

    foreach ($resource in $planResources)
    {
        $resource | Add-Member -Name "product" -value $productDurableId -MemberType NoteProperty
        $resource | Add-Member -Name "plan" -value $planDurableId -MemberType NoteProperty
    }

    PostConfigure -configureSchema $configureSchema -resources $planResources
}

function Publish {
    param (
        [String] $configureSchema,
        [String] $productDurableId,
        [String] $targetType
    )

    $submission = @{
        "`$schema" = "https://product-ingestion.azureedge.net/schema/submission/2022-03-01-preview2"
        "product" = $productDurableId
        "target" = @{
            "targetType" = $targetType
        }
    }
    $resources = @($submission)

    PostConfigure -configureSchema $configureSchema -resources $resources
}