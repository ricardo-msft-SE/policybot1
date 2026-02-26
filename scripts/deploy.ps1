# ============================================================================
# Policy Bot - Deployment Script (PowerShell)
# ============================================================================
# This script deploys all Azure resources required for Policy Bot
# Run from the repository root directory
# ============================================================================

param(
    [Parameter(Mandatory = $false)]
    [string]$ResourceGroupName = "rg-policybot",

    [Parameter(Mandatory = $false)]
    [string]$Location = "eastus2",

    [Parameter(Mandatory = $false)]
    [ValidateSet("basic", "standard", "standard2", "standard3")]
    [string]$SearchSku = "basic",

    [Parameter(Mandatory = $false)]
    [int]$SearchReplicaCount = 1,

    [Parameter(Mandatory = $false)]
    [switch]$SkipResourceGroupCreation,

    [Parameter(Mandatory = $false)]
    [switch]$WhatIf
)

# ============================================================================
# Configuration
# ============================================================================

$ErrorActionPreference = "Stop"
$InformationPreference = "Continue"

# Colors for output
function Write-Step { param($Message) Write-Host "`n>> $Message" -ForegroundColor Cyan }
function Write-Success { param($Message) Write-Host "   [OK] $Message" -ForegroundColor Green }
function Write-Warning { param($Message) Write-Host "   [!] $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "   [X] $Message" -ForegroundColor Red }

# ============================================================================
# Prerequisites Check
# ============================================================================

Write-Step "Checking prerequisites..."

# Check Azure CLI
try {
    $azVersion = az version --output json | ConvertFrom-Json
    Write-Success "Azure CLI version: $($azVersion.'azure-cli')"
}
catch {
    Write-Error "Azure CLI not found. Install from: https://docs.microsoft.com/cli/azure/install-azure-cli"
    exit 1
}

# Check login status
$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    Write-Warning "Not logged in to Azure. Running 'az login'..."
    az login
    $account = az account show --output json | ConvertFrom-Json
}
Write-Success "Logged in as: $($account.user.name)"
Write-Success "Subscription: $($account.name)"

# ============================================================================
# Register Resource Providers
# ============================================================================

Write-Step "Registering required resource providers..."

$providers = @(
    "Microsoft.Search",
    "Microsoft.CognitiveServices",
    "Microsoft.Insights",
    "Microsoft.OperationalInsights"
)

foreach ($provider in $providers) {
    $status = az provider show --namespace $provider --query "registrationState" -o tsv 2>$null
    if ($status -ne "Registered") {
        Write-Host "   Registering $provider..." -NoNewline
        az provider register --namespace $provider --wait
        Write-Success "$provider registered"
    }
    else {
        Write-Success "$provider already registered"
    }
}

# ============================================================================
# Create Resource Group
# ============================================================================

if (-not $SkipResourceGroupCreation) {
    Write-Step "Creating resource group: $ResourceGroupName"
    
    $rgExists = az group exists --name $ResourceGroupName
    if ($rgExists -eq "true") {
        Write-Warning "Resource group '$ResourceGroupName' already exists"
    }
    else {
        if ($WhatIf) {
            Write-Host "   [WhatIf] Would create resource group: $ResourceGroupName in $Location"
        }
        else {
            az group create --name $ResourceGroupName --location $Location --output none
            Write-Success "Resource group created"
        }
    }
}

# ============================================================================
# Deploy Infrastructure
# ============================================================================

Write-Step "Deploying infrastructure with Bicep..."

$templateFile = Join-Path $PSScriptRoot "..\infra\main.bicep"

if (-not (Test-Path $templateFile)) {
    Write-Error "Bicep template not found at: $templateFile"
    exit 1
}

$deploymentParams = @{
    location            = $Location
    searchSku           = $SearchSku
    searchReplicaCount  = $SearchReplicaCount
    enableSemanticSearch = $true
}

$paramsJson = $deploymentParams | ConvertTo-Json -Compress

if ($WhatIf) {
    Write-Host "   [WhatIf] Would deploy with parameters:"
    Write-Host "   $paramsJson"
    
    az deployment group what-if `
        --resource-group $ResourceGroupName `
        --template-file $templateFile `
        --parameters location=$Location searchSku=$SearchSku searchReplicaCount=$SearchReplicaCount
}
else {
    Write-Host "   Deploying resources (this may take 5-10 minutes)..."
    
    $deployment = az deployment group create `
        --resource-group $ResourceGroupName `
        --template-file $templateFile `
        --parameters location=$Location searchSku=$SearchSku searchReplicaCount=$SearchReplicaCount `
        --output json | ConvertFrom-Json
    
    if ($deployment.properties.provisioningState -eq "Succeeded") {
        Write-Success "Deployment completed successfully!"
    }
    else {
        Write-Error "Deployment failed: $($deployment.properties.error.message)"
        exit 1
    }
}

# ============================================================================
# Display Outputs
# ============================================================================

Write-Step "Deployment Outputs:"

if (-not $WhatIf) {
    $outputs = az deployment group show `
        --resource-group $ResourceGroupName `
        --name "main" `
        --query "properties.outputs" `
        --output json | ConvertFrom-Json

    Write-Host ""
    Write-Host "   Resource Group:      $ResourceGroupName" -ForegroundColor White
    Write-Host "   Location:            $($outputs.location.value)" -ForegroundColor White
    Write-Host ""
    Write-Host "   AI Search Service:   $($outputs.searchServiceName.value)" -ForegroundColor White
    Write-Host "   AI Search Endpoint:  $($outputs.searchEndpoint.value)" -ForegroundColor White
    Write-Host ""
    Write-Host "   OpenAI Service:      $($outputs.openAiServiceName.value)" -ForegroundColor White
    Write-Host "   OpenAI Endpoint:     $($outputs.openAiEndpoint.value)" -ForegroundColor White
    Write-Host ""
    Write-Host "   AI Services:         $($outputs.aiServicesName.value)" -ForegroundColor White
    Write-Host "   AI Services Endpoint: $($outputs.aiServicesEndpoint.value)" -ForegroundColor White
    Write-Host ""
    Write-Host "   App Insights:        $($outputs.appInsightsName.value)" -ForegroundColor White
}

# ============================================================================
# Next Steps
# ============================================================================

Write-Step "Next Steps:"

Write-Host @"

   1. Configure Azure AI Search crawler:
      - Navigate to Azure Portal > AI Search > $($outputs.searchServiceName.value)
      - Create a data source pointing to: https://codes.ohio.gov/ohio-revised-code
      - Set crawl depth to 10+
      
   2. Create the Foundry Agent:
      - Navigate to https://ai.azure.com
      - Create a new project
      - Create a Prompt Agent with the system prompt from: foundry/prompts/system-prompt.md
      - Connect to your AI Search index

   3. Test the agent:
      - Use the Foundry chat interface
      - Verify citations are included in responses

   Documentation: docs/deployment-guide.md

"@ -ForegroundColor Gray

Write-Success "Deployment script completed!"
