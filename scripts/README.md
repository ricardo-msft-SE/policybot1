# Scripts

> Helper scripts for deploying and configuring Policy Bot

---

## Overview

This directory contains scripts to automate the deployment and configuration of Policy Bot infrastructure.

---

## Available Scripts

| Script | Platform | Purpose |
|--------|----------|---------|
| `deploy.ps1` | PowerShell | Deploy infrastructure to Azure |
| `deploy.sh` | Bash/Linux/Mac | Deploy infrastructure to Azure |
| `configure-crawler.ps1` | PowerShell | Configure AI Search web crawler |

---

## deploy.ps1 / deploy.sh

Automated deployment script that:
1. Checks prerequisites (Azure CLI, login status)
2. Registers required resource providers
3. Creates resource group
4. Deploys Bicep templates
5. Displays deployment outputs

### Usage (PowerShell)

```powershell
# Basic deployment
.\scripts\deploy.ps1

# With parameters
.\scripts\deploy.ps1 `
    -ResourceGroupName "rg-policybot-prod" `
    -Location "westus2" `
    -SearchSku "standard"

# Preview changes (what-if)
.\scripts\deploy.ps1 -WhatIf
```

### Usage (Bash)

```bash
# Make executable
chmod +x scripts/deploy.sh

# Basic deployment
./scripts/deploy.sh

# With environment variables
RESOURCE_GROUP=rg-policybot-prod \
LOCATION=westus2 \
SEARCH_SKU=standard \
./scripts/deploy.sh
```

### Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `ResourceGroupName` | `rg-policybot` | Azure resource group name |
| `Location` | `eastus2` | Azure region |
| `SearchSku` | `basic` | AI Search tier |
| `SearchReplicaCount` | `1` | Number of search replicas |
| `WhatIf` | `false` | Preview mode (no changes) |

---

## configure-crawler.ps1

Configures Azure AI Search for web crawling of government websites.

### Usage

```powershell
.\scripts\configure-crawler.ps1 `
    -ResourceGroupName "rg-policybot" `
    -SearchServiceName "search-policybot-xyz"

# With custom settings
.\scripts\configure-crawler.ps1 `
    -ResourceGroupName "rg-policybot" `
    -SearchServiceName "search-policybot-xyz" `
    -IndexName "ohio-code-index" `
    -SeedUrl "https://codes.ohio.gov/ohio-revised-code" `
    -CrawlDepth 10
```

### What It Does

1. Connects to your Azure AI Search service
2. Creates the search index with proper schema
3. Outputs configuration for the web crawler
4. Saves configuration to `foundry/search-config.json`

### Manual Steps Required

Azure AI Search web crawling for external websites requires configuration through the Azure Portal. The script prepares the index and provides instructions for:

1. Creating the web data source
2. Configuring crawl depth and scope
3. Setting up the indexer schedule

---

## Prerequisites

All scripts require:

- **Azure CLI** (version 2.20.0+)
  ```bash
  az --version
  ```

- **Azure subscription access**
  ```bash
  az login
  ```

- **Contributor role** on the subscription or resource group

---

## Troubleshooting

### Script execution policy (PowerShell)

If you get "running scripts is disabled":

```powershell
# Check current policy
Get-ExecutionPolicy

# Allow scripts (current user)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Bash script permissions

If you get "permission denied":

```bash
chmod +x scripts/deploy.sh
```

### Azure CLI not found

Install from: https://docs.microsoft.com/cli/azure/install-azure-cli

### Login issues

```bash
# Clear cached credentials
az account clear

# Login again
az login
```

---

## Related Documentation

- [Deployment Guide](../docs/deployment-guide.md) - Full step-by-step instructions
- [Infrastructure README](../infra/README.md) - Bicep template details
