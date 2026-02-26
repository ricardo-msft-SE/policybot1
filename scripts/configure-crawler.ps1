# ============================================================================
# Policy Bot - Web Crawler Configuration Script
# ============================================================================
# This script configures the Azure AI Search web crawler for deep indexing
# of government websites like codes.ohio.gov
# ============================================================================

param(
    [Parameter(Mandatory = $true)]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true)]
    [string]$SearchServiceName,

    [Parameter(Mandatory = $false)]
    [string]$IndexName = "policy-index",

    [Parameter(Mandatory = $false)]
    [string]$DataSourceName = "ohio-code-datasource",

    [Parameter(Mandatory = $false)]
    [string]$IndexerName = "ohio-code-indexer",

    [Parameter(Mandatory = $false)]
    [string]$SeedUrl = "https://codes.ohio.gov/ohio-revised-code",

    [Parameter(Mandatory = $false)]
    [int]$CrawlDepth = 10
)

$ErrorActionPreference = "Stop"

# ============================================================================
# Get Search Service Details
# ============================================================================

Write-Host "`n>> Getting Search Service details..." -ForegroundColor Cyan

$searchEndpoint = "https://$SearchServiceName.search.windows.net"
$adminKey = az search admin-key show `
    --resource-group $ResourceGroupName `
    --service-name $SearchServiceName `
    --query "primaryKey" `
    -o tsv

if (-not $adminKey) {
    Write-Host "   [X] Failed to get admin key" -ForegroundColor Red
    exit 1
}

Write-Host "   [OK] Search endpoint: $searchEndpoint" -ForegroundColor Green

# Common headers
$headers = @{
    "Content-Type" = "application/json"
    "api-key"      = $adminKey
}

# ============================================================================
# Create Index
# ============================================================================

Write-Host "`n>> Creating search index: $IndexName" -ForegroundColor Cyan

$indexDefinition = @{
    name = $IndexName
    fields = @(
        @{ name = "id"; type = "Edm.String"; key = $true; searchable = $false }
        @{ name = "content"; type = "Edm.String"; searchable = $true; analyzer = "en.microsoft" }
        @{ name = "title"; type = "Edm.String"; searchable = $true; filterable = $true; sortable = $true }
        @{ name = "url"; type = "Edm.String"; searchable = $false; filterable = $true; retrievable = $true }
        @{ name = "lastModified"; type = "Edm.DateTimeOffset"; filterable = $true; sortable = $true }
        @{ name = "breadcrumb"; type = "Edm.String"; searchable = $true; retrievable = $true }
        @{ name = "metadata_storage_path"; type = "Edm.String"; searchable = $false; retrievable = $true }
    )
    semantic = @{
        configurations = @(
            @{
                name = "policy-semantic-config"
                prioritizedFields = @{
                    titleField = @{ fieldName = "title" }
                    contentFields = @(
                        @{ fieldName = "content" }
                    )
                }
            }
        )
    }
} | ConvertTo-Json -Depth 10

try {
    $response = Invoke-RestMethod `
        -Uri "$searchEndpoint/indexes/$IndexName`?api-version=2023-11-01" `
        -Method Put `
        -Headers $headers `
        -Body $indexDefinition
    
    Write-Host "   [OK] Index created/updated successfully" -ForegroundColor Green
}
catch {
    Write-Host "   [X] Failed to create index: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# ============================================================================
# Create Data Source
# ============================================================================

Write-Host "`n>> Creating data source: $DataSourceName" -ForegroundColor Cyan

# Note: Web data source requires enabling the preview feature
# For production, you may need to use a different approach like:
# 1. Custom web scraper that writes to Azure Blob Storage
# 2. Azure Logic Apps or Functions for web scraping
# 3. Third-party web crawling services

Write-Host @"
   
   [!] IMPORTANT: Azure AI Search web crawler for external websites requires 
       configuration through the Azure Portal or REST API with preview features.
   
   Manual Steps Required:
   
   1. Navigate to Azure Portal > AI Search > $SearchServiceName
   
   2. Click "Import data" > "Web content"
   
   3. Configure the data source:
      - Seed URL: $SeedUrl
      - Crawl depth: $CrawlDepth
      - Restrict to: codes.ohio.gov/*
   
   4. Configure the index (already created above)
   
   5. Create the indexer:
      - Name: $IndexerName
      - Schedule: Weekly
   
   Alternative approach for production:
   - Use Azure Function to crawl the website
   - Store content in Azure Blob Storage
   - Index from Blob Storage (fully supported)
   
"@ -ForegroundColor Yellow

# ============================================================================
# Create Sample Skillset (for AI enrichment)
# ============================================================================

Write-Host "`n>> Sample skillset configuration..." -ForegroundColor Cyan

$skillsetDefinition = @{
    name = "policy-skillset"
    description = "Skillset for policy document enrichment"
    skills = @(
        @{
            "@odata.type" = "#Microsoft.Skills.Text.SplitSkill"
            name = "split-skill"
            description = "Split content into chunks"
            context = "/document"
            inputs = @(
                @{ name = "text"; source = "/document/content" }
            )
            outputs = @(
                @{ name = "textItems"; targetName = "chunks" }
            )
            textSplitMode = "pages"
            maximumPageLength = 2048
            pageOverlapLength = 256
        }
        @{
            "@odata.type" = "#Microsoft.Skills.Text.KeyPhraseExtractionSkill"
            name = "keyphrase-skill"
            description = "Extract key phrases"
            context = "/document"
            inputs = @(
                @{ name = "text"; source = "/document/content" }
            )
            outputs = @(
                @{ name = "keyPhrases"; targetName = "keyphrases" }
            )
        }
    )
} | ConvertTo-Json -Depth 10

Write-Host "   [INFO] Skillset definition prepared (apply via Portal or REST API)" -ForegroundColor Gray

# ============================================================================
# Output Configuration Summary
# ============================================================================

Write-Host "`n>> Configuration Summary" -ForegroundColor Cyan
Write-Host ""
Write-Host "   Search Service:   $SearchServiceName"
Write-Host "   Search Endpoint:  $searchEndpoint"
Write-Host "   Index Name:       $IndexName"
Write-Host "   Target URL:       $SeedUrl"
Write-Host "   Crawl Depth:      $CrawlDepth"
Write-Host ""

# Save configuration to file
$config = @{
    searchService = $SearchServiceName
    endpoint = $searchEndpoint
    indexName = $IndexName
    seedUrl = $SeedUrl
    crawlDepth = $CrawlDepth
    createdAt = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")
} | ConvertTo-Json

$configPath = Join-Path $PSScriptRoot "..\foundry\search-config.json"
$config | Out-File -FilePath $configPath -Encoding UTF8

Write-Host "   Configuration saved to: $configPath" -ForegroundColor Green
Write-Host ""
Write-Host "   [OK] Crawler configuration script completed!" -ForegroundColor Green
Write-Host ""
Write-Host "   Next: Configure the web crawler in Azure Portal" -ForegroundColor Yellow
