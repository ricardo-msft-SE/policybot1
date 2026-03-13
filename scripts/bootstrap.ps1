# ============================================================================
# Policy Bot - Complete Bootstrap Script
# ============================================================================
# End-to-end setup: Azure infrastructure, Foundry Hub/Project, AI Search
# indexing of Ohio Revised Code Title 45, Foundry agent creation.
#
# Prerequisites:
#   az cli installed and authenticated  (or will be prompted)
#   Python 3.10+  on PATH
#   pip install -r requirements.txt  (or pass -InstallPackages)
#
# Usage (from repo root):
#   .\scripts\bootstrap.ps1
#   .\scripts\bootstrap.ps1 -Location "eastus"
#   .\scripts\bootstrap.ps1 -WhatIf
# ============================================================================

param(
    [string]$SubscriptionId  = "ee0073ce-de38-45ed-a940-4dbfd9435dc1",
    [string]$ResourceGroupName = "rg-policybot",
    [string]$Location          = "eastus2",
    [string]$HubName           = "policybot-hub",
    [string]$ProjectName       = "policybot-project",
    [switch]$InstallPackages,
    [switch]$SkipInfra,
    [switch]$SkipIndexing,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"

# ── helpers ──────────────────────────────────────────────────────────────────
function Step   { param($m) Write-Host "`n>> $m" -ForegroundColor Cyan }
function Ok     { param($m) Write-Host "   [OK] $m"  -ForegroundColor Green }
function Warn   { param($m) Write-Host "   [!]  $m"  -ForegroundColor Yellow }
function Fail   { param($m) Write-Host "   [X]  $m"  -ForegroundColor Red; exit 1 }
function Banner { param($m) Write-Host "`n$('='*60)`n  $m`n$('='*60)" -ForegroundColor Magenta }

Banner "Policy Bot – Ohio Revised Code Title 45 Chatbot"

# ============================================================================
# 0. Prerequisites
# ============================================================================
Step "Checking prerequisites"

# Azure CLI
try { $null = az version 2>&1 } catch { Fail "Azure CLI not found. Install: https://aka.ms/installazurecliwindows" }
Ok "Azure CLI found"

# Python
try { $pyVer = python --version 2>&1; Ok "Python: $pyVer" } catch { Fail "Python not found. Install from python.org" }

# pip packages
if ($InstallPackages) {
    Step "Installing Python dependencies"
    pip install -r (Join-Path $PSScriptRoot "..\requirements.txt") --quiet
    Ok "Dependencies installed"
}

# ============================================================================
# 1. Azure Login & Subscription
# ============================================================================
Step "Setting Azure subscription"

$account = az account show --output json 2>$null | ConvertFrom-Json
if (-not $account) {
    Warn "Not logged in – launching az login"
    az login | Out-Null
}

if ($WhatIf) { Warn "[WhatIf] Would set subscription $SubscriptionId" }
else {
    az account set --subscription $SubscriptionId
    Ok "Subscription: $SubscriptionId"
}

# ============================================================================
# 2. Register resource providers
# ============================================================================
Step "Registering resource providers"

$providers = @(
    "Microsoft.Search",
    "Microsoft.CognitiveServices",
    "Microsoft.MachineLearningServices",
    "Microsoft.Insights",
    "Microsoft.OperationalInsights",
    "Microsoft.Storage"
)
foreach ($p in $providers) {
    $state = az provider show --namespace $p --query "registrationState" -o tsv 2>$null
    if ($state -ne "Registered") {
        if (-not $WhatIf) {
            az provider register --namespace $p --wait | Out-Null
        }
    }
    Ok "$p"
}

# ============================================================================
# 3. Resource Group
# ============================================================================
Step "Creating resource group: $ResourceGroupName"

if (-not $WhatIf) {
    $rgExists = az group exists --name $ResourceGroupName
    if ($rgExists -eq "false") {
        az group create --name $ResourceGroupName --location $Location --output none
        Ok "Resource group created"
    } else {
        Ok "Resource group already exists"
    }
}

# ============================================================================
# 4. Deploy Infrastructure (Bicep)
# ============================================================================
if (-not $SkipInfra) {
    Step "Deploying Bicep infrastructure (AI Search, OpenAI, AI Services, App Insights)"

    $templateFile = Join-Path $PSScriptRoot "..\infra\main.bicep"
    if (-not (Test-Path $templateFile)) { Fail "Bicep template not found: $templateFile" }

    if ($WhatIf) {
        Warn "[WhatIf] Would deploy $templateFile to $ResourceGroupName"
    } else {
        Write-Host "   Deploying... (5-10 min)" -ForegroundColor Gray
        $dep = az deployment group create `
            --resource-group $ResourceGroupName `
            --template-file $templateFile `
            --parameters "location=$Location" `
            --output json | ConvertFrom-Json

        if ($dep.properties.provisioningState -ne "Succeeded") {
            Fail "Bicep deployment failed: $($dep.properties.error.message)"
        }
        Ok "Infrastructure deployed"
    }
}

# Read deployment outputs
Step "Reading deployment outputs"

if ($WhatIf) {
    $SearchServiceName   = "search-policybot-PREVIEW"
    $SearchEndpoint      = "https://search-policybot-PREVIEW.search.windows.net"
    $OpenAiEndpoint      = "https://aoai-policybot-PREVIEW.openai.azure.com/"
    $AiServicesName      = "ais-policybot-PREVIEW"
    $AiServicesEndpoint  = "https://ais-policybot-PREVIEW.cognitiveservices.azure.com/"
} else {
    $outputs = az deployment group show `
        --resource-group $ResourceGroupName `
        --name "main" `
        --query "properties.outputs" `
        --output json | ConvertFrom-Json

    $SearchServiceName   = $outputs.searchServiceName.value
    $SearchEndpoint      = $outputs.searchEndpoint.value
    $OpenAiEndpoint      = $outputs.openAiEndpoint.value
    $AiServicesName      = $outputs.aiServicesName.value
    $AiServicesEndpoint  = $outputs.aiServicesEndpoint.value

    Ok "AI Search:    $SearchEndpoint"
    Ok "OpenAI:       $OpenAiEndpoint"
    Ok "AI Services:  $AiServicesEndpoint"
}

# ============================================================================
# 5. Deploy Models to AI Services (for Foundry agent)
# ============================================================================
Step "Deploying models to AI Services (gpt-4o + text-embedding-3-small)"

if (-not $WhatIf) {
    # gpt-4o for chat
    $existingDeployment = az cognitiveservices account deployment show `
        --resource-group $ResourceGroupName `
        --name $AiServicesName `
        --deployment-name "gpt-4o" `
        --output json 2>$null | ConvertFrom-Json

    if (-not $existingDeployment) {
        Write-Host "   Deploying gpt-4o..." -ForegroundColor Gray
        az cognitiveservices account deployment create `
            --resource-group $ResourceGroupName `
            --name $AiServicesName `
            --deployment-name "gpt-4o" `
            --model-name "gpt-4o" `
            --model-version "2024-08-06" `
            --model-format "OpenAI" `
            --sku-name "GlobalStandard" `
            --sku-capacity 30 `
            --output none
        Ok "gpt-4o deployed"
    } else { Ok "gpt-4o already deployed" }

    # text-embedding-3-small for vector search
    $existingEmbed = az cognitiveservices account deployment show `
        --resource-group $ResourceGroupName `
        --name $AiServicesName `
        --deployment-name "text-embedding-3-small" `
        --output json 2>$null | ConvertFrom-Json

    if (-not $existingEmbed) {
        Write-Host "   Deploying text-embedding-3-small..." -ForegroundColor Gray
        az cognitiveservices account deployment create `
            --resource-group $ResourceGroupName `
            --name $AiServicesName `
            --deployment-name "text-embedding-3-small" `
            --model-name "text-embedding-3-small" `
            --model-version "1" `
            --model-format "OpenAI" `
            --sku-name "Standard" `
            --sku-capacity 120 `
            --output none
        Ok "text-embedding-3-small deployed"
    } else { Ok "text-embedding-3-small already deployed" }
}

# ============================================================================
# 6. Create Foundry Hub & Project
# ============================================================================
Step "Setting up Azure AI Foundry Hub and Project"

if (-not $WhatIf) {
    # Ensure az ml extension is installed
    $mlExt = az extension show --name ml --output json 2>$null | ConvertFrom-Json
    if (-not $mlExt) {
        Write-Host "   Installing az ml extension..." -ForegroundColor Gray
        az extension add --name ml --yes --output none
        Ok "az ml extension installed"
    } else { Ok "az ml extension available" }

    # AI Services resource ID for hub connection
    $AiServicesResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.CognitiveServices/accounts/$AiServicesName"

    # Create storage account for Foundry Hub (required)
    $StorageAccountName = "stpolicybot$(([guid]::NewGuid().ToString().Replace('-',''))[0..7] -join '')"
    $existingStorage = az storage account show --name $StorageAccountName --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json
    if (-not $existingStorage) {
        # Use a deterministic name based on resource group name
        $hashBytes = [System.Text.Encoding]::UTF8.GetBytes($ResourceGroupName + $SubscriptionId)
        $storageSuffix = ([System.BitConverter]::ToString([System.Security.Cryptography.MD5]::Create().ComputeHash($hashBytes)) -replace '-','').Substring(0,8).ToLower()
        $StorageAccountName = "stpltbot$storageSuffix"
        Write-Host "   Creating storage for Foundry Hub: $StorageAccountName" -ForegroundColor Gray
        az storage account create `
            --name $StorageAccountName `
            --resource-group $ResourceGroupName `
            --location $Location `
            --sku Standard_LRS `
            --kind StorageV2 `
            --output none
        Ok "Storage account created: $StorageAccountName"
    } else { Ok "Storage account exists" }

    $StorageResourceId = az storage account show --name $StorageAccountName --resource-group $ResourceGroupName --query id -o tsv

    # Create Foundry Hub
    $hubExists = az ml workspace show --name $HubName --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json
    if (-not $hubExists) {
        Write-Host "   Creating Foundry Hub: $HubName..." -ForegroundColor Gray
        az ml workspace create `
            --name $HubName `
            --resource-group $ResourceGroupName `
            --location $Location `
            --kind Hub `
            --storage-account $StorageResourceId `
            --output none
        Ok "Foundry Hub created: $HubName"
    } else { Ok "Foundry Hub already exists: $HubName" }

    $HubResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.MachineLearningServices/workspaces/$HubName"

    # Connect AI Services to Hub
    $connName = "aiservices-conn"
    $connCheck = az ml connection show --name $connName --workspace-name $HubName --resource-group $ResourceGroupName --output json 2>$null
    if (-not $connCheck) {
        Write-Host "   Connecting AI Services to Hub..." -ForegroundColor Gray
        $connYaml = @"
name: $connName
type: azure_ai_services
endpoint: $AiServicesEndpoint
resource_id: $AiServicesResourceId
is_shared: true
"@
        $connFile = [System.IO.Path]::GetTempFileName() + ".yaml"
        $connYaml | Set-Content $connFile -Encoding UTF8
        az ml connection create `
            --file $connFile `
            --workspace-name $HubName `
            --resource-group $ResourceGroupName `
            --output none
        Remove-Item $connFile
        Ok "AI Services connected to Hub"
    } else { Ok "AI Services connection already exists" }

    # Connect AI Search to Hub
    $searchKey = az search admin-key show --resource-group $ResourceGroupName --service-name $SearchServiceName --query primaryKey -o tsv
    $searchConnName = "aisearch-conn"
    $searchConnCheck = az ml connection show --name $searchConnName --workspace-name $HubName --resource-group $ResourceGroupName --output json 2>$null
    if (-not $searchConnCheck) {
        Write-Host "   Connecting AI Search to Hub..." -ForegroundColor Gray
        $searchConnYaml = @"
name: $searchConnName
type: azure_ai_search
endpoint: $SearchEndpoint
api_key: $searchKey
is_shared: true
"@
        $searchConnFile = [System.IO.Path]::GetTempFileName() + ".yaml"
        $searchConnYaml | Set-Content $searchConnFile -Encoding UTF8
        az ml connection create `
            --file $searchConnFile `
            --workspace-name $HubName `
            --resource-group $ResourceGroupName `
            --output none
        Remove-Item $searchConnFile
        Ok "AI Search connected to Hub"
    } else { Ok "AI Search connection already exists" }

    # Create Foundry Project
    $projectExists = az ml workspace show --name $ProjectName --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json
    if (-not $projectExists) {
        Write-Host "   Creating Foundry Project: $ProjectName..." -ForegroundColor Gray
        az ml workspace create `
            --name $ProjectName `
            --resource-group $ResourceGroupName `
            --kind Project `
            --hub-id $HubResourceId `
            --output none
        Ok "Foundry Project created: $ProjectName"
    } else { Ok "Foundry Project already exists: $ProjectName" }

    # Get project endpoint for AIProjectClient
    $projectInfo = az ml workspace show --name $ProjectName --resource-group $ResourceGroupName --output json | ConvertFrom-Json
    # The discovered URL format for AIProjectClient
    $discoveryUrl = $projectInfo.discovery_url
    # Construct the API endpoint from discovery URL
    if ($discoveryUrl -match "https://([^/]+)/") {
        $apiHost = $Matches[1]
        $ProjectEndpoint = "https://$apiHost/api/projects/$ProjectName"
    } else {
        $ProjectEndpoint = $AiServicesEndpoint.TrimEnd('/') + "/api/projects/$ProjectName"
    }
    Ok "Project endpoint: $ProjectEndpoint"
}

# ============================================================================
# 7. Configure AI Search Index for Title 45
# ============================================================================
Step "Configuring AI Search index"

if (-not $WhatIf) {
    $env:AZURE_SEARCH_ENDPOINT  = $SearchEndpoint
    $env:AZURE_OPENAI_ENDPOINT  = $AiServicesEndpoint
    $env:AZURE_EMBEDDING_MODEL  = "text-embedding-3-small"
    $env:AZURE_SEARCH_INDEX     = "ohio-title45-index"
    $env:CRAWL_URL              = "https://codes.ohio.gov/ohio-revised-code/title-45"

    Write-Host "   Creating search index schema..." -ForegroundColor Gray
    python (Join-Path $PSScriptRoot "configure-search.py") create-index
    Ok "Search index configured"
}

# ============================================================================
# Done – Next Steps in the Portal
# ============================================================================
Banner "Infrastructure deployed. Complete setup in the portal."

Write-Host ""
Write-Host "  Resources created in: $ResourceGroupName ($Location)" -ForegroundColor White
Write-Host "  ──────────────────────────────────────────────────────" -ForegroundColor Gray
if (-not $WhatIf) {
    Write-Host "  AI Search:      $SearchEndpoint" -ForegroundColor Cyan
    Write-Host "  AI Services:    $AiServicesEndpoint" -ForegroundColor Cyan
    Write-Host "  Foundry Hub:    $HubName" -ForegroundColor Cyan
    Write-Host "  Foundry Project:$ProjectName" -ForegroundColor Cyan
}
Write-Host ""
Write-Host "  NEXT STEPS (in the portal):" -ForegroundColor Yellow
Write-Host ""
Write-Host "  1. INDEX TITLE 45" -ForegroundColor White
Write-Host "     Portal: AI Search ($SearchServiceName)" -ForegroundColor Gray
Write-Host "     Click: 'Import and vectorize data'" -ForegroundColor Gray
Write-Host "     Seed URL:   https://codes.ohio.gov/ohio-revised-code/title-45" -ForegroundColor Gray
Write-Host "     Embedding:  text-embedding-3-small" -ForegroundColor Gray
Write-Host "     Index name: ohio-title45-index" -ForegroundColor Gray
Write-Host "     Depth:      10" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. CREATE AGENT" -ForegroundColor White
Write-Host "     Portal: https://ai.azure.com -> Project: $ProjectName" -ForegroundColor Gray
Write-Host "     Agents -> New agent -> Name: ohio-title45-bot" -ForegroundColor Gray
Write-Host "     Model: gpt-4o  Temperature: 0.1" -ForegroundColor Gray
Write-Host "     Paste system prompt from: foundry/prompts/system-prompt.md" -ForegroundColor Gray
Write-Host "     Add knowledge: aisearch-conn / ohio-title45-index" -ForegroundColor Gray
Write-Host "     Top K: 10  Strictness: 4  In scope only: ON" -ForegroundColor Gray
Write-Host ""
Write-Host "  3. TEST & DEPLOY" -ForegroundColor White
Write-Host "     Chat Playground -> test -> Deploy -> As a web app" -ForegroundColor Gray
Write-Host ""
Write-Host "  Full guide: https://ricardo-msft-SE.github.io/policybot1/deployment-guide" -ForegroundColor Green
Write-Host ""
