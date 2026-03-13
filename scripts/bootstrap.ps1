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
# 5. Deploy Models to AI Services (for Foundry agents)
# ============================================================================
Step "Deploying models to AI Services (gpt-4o, gpt-4o-mini, o3-mini, text-embedding-3-small)"

if (-not $WhatIf) {
    # gpt-4o — Orchestrator, Definitions Agent, Traffic & Violations Agent
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

    # gpt-4o-mini — Licensing & Registration Agent (lower cost for procedural queries)
    $existingMini = az cognitiveservices account deployment show `
        --resource-group $ResourceGroupName `
        --name $AiServicesName `
        --deployment-name "gpt-4o-mini" `
        --output json 2>$null | ConvertFrom-Json

    if (-not $existingMini) {
        Write-Host "   Deploying gpt-4o-mini..." -ForegroundColor Gray
        az cognitiveservices account deployment create `
            --resource-group $ResourceGroupName `
            --name $AiServicesName `
            --deployment-name "gpt-4o-mini" `
            --model-name "gpt-4o-mini" `
            --model-version "2024-07-18" `
            --model-format "OpenAI" `
            --sku-name "GlobalStandard" `
            --sku-capacity 30 `
            --output none
        Ok "gpt-4o-mini deployed"
    } else { Ok "gpt-4o-mini already deployed" }

    # o3-mini — Legal Reasoning Agent (reasoning model; temp must be 1 in Foundry)
    $existingO3 = az cognitiveservices account deployment show `
        --resource-group $ResourceGroupName `
        --name $AiServicesName `
        --deployment-name "o3-mini" `
        --output json 2>$null | ConvertFrom-Json

    if (-not $existingO3) {
        Write-Host "   Deploying o3-mini..." -ForegroundColor Gray
        az cognitiveservices account deployment create `
            --resource-group $ResourceGroupName `
            --name $AiServicesName `
            --deployment-name "o3-mini" `
            --model-name "o3-mini" `
            --model-version "2025-01-31" `
            --model-format "OpenAI" `
            --sku-name "GlobalStandard" `
            --sku-capacity 10 `
            --output none
        Ok "o3-mini deployed"
    } else { Ok "o3-mini already deployed" }

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
# 6. Create Foundry Project (hub-less — new AI Foundry model)
# ============================================================================
# The new Azure AI Foundry model does NOT require a Hub workspace.
# A Project is created directly, linked to the AI Services account via
# --hub-id pointing to the CognitiveServices resource ID.
# ============================================================================
Step "Setting up Azure AI Foundry Project (hub-less)"

if (-not $WhatIf) {
    # Ensure az ml extension is installed
    $mlExt = az extension show --name ml --output json 2>$null | ConvertFrom-Json
    if (-not $mlExt) {
        Write-Host "   Installing az ml extension..." -ForegroundColor Gray
        az extension add --name ml --yes --output none
        Ok "az ml extension installed"
    } else { Ok "az ml extension available" }

    # AI Services resource ID — the Project links to this directly (no Hub needed)
    $AiServicesResourceId = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.CognitiveServices/accounts/$AiServicesName"

    # Create Foundry Project linked directly to AI Services (hub-less)
    $projectExists = az ml workspace show --name $ProjectName --resource-group $ResourceGroupName --output json 2>$null | ConvertFrom-Json
    if (-not $projectExists) {
        Write-Host "   Creating Foundry Project: $ProjectName (hub-less)..." -ForegroundColor Gray
        az ml workspace create `
            --name $ProjectName `
            --resource-group $ResourceGroupName `
            --location $Location `
            --kind Project `
            --hub-id $AiServicesResourceId `
            --output none
        Ok "Foundry Project created: $ProjectName"
    } else { Ok "Foundry Project already exists: $ProjectName" }

    # Connect AI Search directly to the Project
    $searchKey = az search admin-key show --resource-group $ResourceGroupName --service-name $SearchServiceName --query primaryKey -o tsv
    $searchConnName = "aisearch-conn"
    $searchConnCheck = az ml connection show --name $searchConnName --workspace-name $ProjectName --resource-group $ResourceGroupName --output json 2>$null
    if (-not $searchConnCheck) {
        Write-Host "   Connecting AI Search to Project..." -ForegroundColor Gray
        $searchConnYaml = @"
name: $searchConnName
type: azure_ai_search
endpoint: $SearchEndpoint
api_key: $searchKey
"@
        $searchConnFile = [System.IO.Path]::GetTempFileName() + ".yaml"
        $searchConnYaml | Set-Content $searchConnFile -Encoding UTF8
        az ml connection create `
            --file $searchConnFile `
            --workspace-name $ProjectName `
            --resource-group $ResourceGroupName `
            --output none
        Remove-Item $searchConnFile
        Ok "AI Search connected to Project ($searchConnName)"
    } else { Ok "AI Search connection already exists" }
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
Write-Host "  2. CREATE AGENTS (portal: https://ai.azure.com -> Project: $ProjectName)" -ForegroundColor White
Write-Host "     Create specialists FIRST (in this order), Orchestrator LAST:" -ForegroundColor Gray
Write-Host "     1. definitions-agent         gpt-4o      temp=0" -ForegroundColor Gray
Write-Host "     2. traffic-violations-agent  gpt-4o      temp=0" -ForegroundColor Gray
Write-Host "     3. licensing-agent           gpt-4o-mini temp=0.1" -ForegroundColor Gray
Write-Host "     4. legal-reasoning-agent     o3-mini     temp=1 (required)" -ForegroundColor Gray
Write-Host "     5. orchestrator              gpt-4o      temp=0.1 (connect 1-4 as tools)" -ForegroundColor Gray
Write-Host "     Prompts: foundry/prompts/*.md  |  Knowledge: aisearch-conn / ohio-title45-index" -ForegroundColor Gray
Write-Host "     Top K: 10  Strictness: 4  In scope only: ON" -ForegroundColor Gray
Write-Host ""
Write-Host "  3. TEST & DEPLOY" -ForegroundColor White
Write-Host "     Chat Playground -> test -> Deploy -> As a web app" -ForegroundColor Gray
Write-Host ""
Write-Host "  Full guide: https://ricardo-msft-SE.github.io/policybot1/deployment-guide" -ForegroundColor Green
Write-Host ""
