# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.

####################################################################################################
# This script allows you to deploy your solution template offer to your Azure subscription. It     #
# uploads your scripts to a container on your storage account and generates a SAS token for the    #
# "_artifactsLocation" container. The container URI and SAS token is used in place of the          #
# "_artifactsLocation" and "_artifactsLocationSasToken" parameters in the solution template.       #
# These two parameters are usually generated by Azure during the deployment process.               #
####################################################################################################
Param (
    [Parameter(Mandatory = $True, HelpMessage = "Resource group where Azure resources are deployed to")]
    [String] $resourceGroup,
    [Parameter(Mandatory = $True, HelpMessage = "Region where Azure resources are deployed to")]
    [String] $location,
    [Parameter(Mandatory = $True, HelpMessage = "Path to solution assets folder")]
    [String] $assetsFolder,
    [Parameter(Mandatory = $True, HelpMessage = "Parameters file")]
    [String] $parametersFile,
    [Parameter(Mandatory = $True, HelpMessage = "The name of the storage account where resources will be uploaded to")]
    [String] $storageAccountName
)

function Get-ConnectionString {
    param (
        [String] $storageAccountName
    )
    $connectionString = (az storage account show-connection-string --name $storageAccountName -o json | ConvertFrom-Json).connectionString
    return $connectionString
}

$resourceGroupNameRegex = "^[a-zA-Z0-9\.\-_\(\)]{1,89}[a-zA-Z0-9\-_\(\)]{1}$"
$regionRegex = "^[a-z0-9]{1,30}$"

# Validate input parameters
if ($resourceGroup -notmatch $resourceGroupNameRegex) {
    Write-Error "Please provide a valid Resource Group Name."
    Exit 1
}

if ($location -notmatch $regionRegex) {
    Write-Error "Please provide a valid region."
    Exit 1
}

if (-not(Test-Path $assetsFolder)) {
    Write-Error "Please provide a valid assets folder path."
    Exit 1
}

if (-not(Test-Path $parametersFile)) {
    Write-Error "Please provide a valid parameters file path."
    Exit 1
}

$workingDirectory = Get-Item .
$parametersFilePath = Resolve-Path $parametersFile

try
{
    az storage account show-connection-string --name $storageAccountName -o json | ConvertFrom-Json

    $connectionString = Get-ConnectionString $storageAccountName

    Set-Location $assetsFolder

    # Deploy
    Write-Output "Deploying to $resourceGroup in $location using parameters from $parametersFile..."
    az group create -n $resourceGroup -l $location --output none

    $armParameters = (Get-Content -Path mainTemplate.json -Raw | ConvertFrom-Json).parameters
    if ($null -ne $armParameters._artifactsLocation)
    {
        # Upload scripts to storage account
        $containerName = ((Split-Path -Path $assetsFolder -Leaf) + (get-date).ToString("MMddyyhhmmss"))
        Write-Output "Uploading scripts to $containerName in storage account..."
        $conStringLength = $connectionString.Length
        Write-Output "Connection String has $conStringLength characters"
        az storage container create -n $containerName --connection-string $connectionString # --output none
        # az storage blob upload-batch -d ($containerName) -s "." --pattern *.ps1 --connection-string $connectionString --output none
        # $containerLocation = "https://" + $storageAccountName + ".blob.core.windows.net/" + $containerName + "/"

        # # Generate SAS for container
        # Write-Output "Generating SAS to $containerName..."
        # $end = (Get-Date).ToUniversalTime()
        # $end = $end.AddDays(1)
        # $endsas = ($end.ToString("yyyy-MM-ddTHH:mm:ssZ"))
        # $sas = az storage container generate-sas -n $containerName --https-only --permissions r --expiry $endsas -o tsv --connection-string $connectionString
        # $sas = ("?" + $sas)

        # $result = az deployment group create -g $resourceGroup -f mainTemplate.json --parameters "@$parametersFilePath" --parameters location=$location _artifactsLocation=$containerLocation _artifactsLocationSasToken="""$sas"""
    }
    else
    {
        $result = az deployment group create -g $resourceGroup -f mainTemplate.json --parameters "@$parametersFilePath" --parameters location=$location
    }

    if ($result)
    {
        Write-Output "Deployment complete!"
    }
    else
    {
        Write-Error "Deployment failed!"
    }
}
catch
{
    throw $_.Exception.Message
}
finally
{
    if ($null -ne $containerName)
    {
        Write-Output "Cleaning up..."
        az storage container delete -n $containerName --connection-string $connectionString --output none
    }

    Set-Location $workingDirectory
}
