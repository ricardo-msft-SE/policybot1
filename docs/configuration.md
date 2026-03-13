---
layout: default
title: Configuration Reference
nav_order: 5
---

# Configuration Reference
{: .no_toc }

Reference for all tunable settings in the Policy Bot.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Infrastructure (`scripts/bootstrap.ps1` Parameters)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `SubscriptionId` | `ee0073ce-de38-45ed-a940-4dbfd9435dc1` | Azure subscription |
| `ResourceGroupName` | `rg-policybot` | Resource group to deploy into |
| `Location` | `eastus2` | Azure region |
| `HubName` | `policybot-hub` | Foundry Hub name |
| `ProjectName` | `policybot-project` | Foundry Project name |
| `-InstallPackages` | *(switch)* | Installs Python dependencies before running |
| `-SkipInfra` | *(switch)* | Skips Bicep deployment (re-runs connections only) |
| `-SkipIndexing` | *(switch)* | Skips scraper call (if any) |
| `-WhatIf` | *(switch)* | Dry run — prints what would happen, creates nothing |

---

## Agent Settings (`foundry/agent-config.json`)

This file is a **configuration reference** — the actual agent is created in the Foundry portal.
Use these values when filling in the portal form in [Step 3 of the Deployment Guide]({{ site.baseurl }}/deployment-guide#step-3--create-the-foundry-agent).

| Setting | Value | Notes |
|---------|-------|-------|
| `model.deployment` | `gpt-4o` | Match your AI Services deployment name |
| `model.parameters.temperature` | `0.1` | Keep low for factual responses |
| `knowledge.indexName` | `ohio-title45-index` | Must match the index created in Step 2 |
| `knowledge.semanticConfiguration` | `policy-semantic-config` | Must match config in Step 2 |
| `knowledge.queryType` | `vector_semantic_hybrid` | Best for legal text |
| `knowledge.topK` | `10` | Number of chunks retrieved per query |
| `knowledge.strictness` | `4` | 1–5; higher = stricter grounding requirement |
| `knowledge.inScope` | `true` | **Do not change** — prevents out-of-scope answers |

---

## AI Search Index Schema

The "Import and vectorize data" wizard creates these key fields automatically:

| Field | Type | Purpose |
|-------|------|---------|
| `id` | `Edm.String` (key) | Document identifier |
| `content` | `Edm.String` | Full text of the chunk |
| `title` | `Edm.String` | Section heading |
| `url` | `Edm.String` | Source URL on codes.ohio.gov |
| `embedding` | `Collection(Edm.Single)` | 1536-dim vector from `text-embedding-3-small` |

---

## Web Crawler Settings

Configure in **Azure Portal → AI Search → Indexers → `ohio-title45-indexer`**:

| Setting | Recommended Value |
|---------|------------------|
| Seed URL | `https://codes.ohio.gov/ohio-revised-code/title-45` |
| Crawl depth | `10` |
| Scope | Restricted to `codes.ohio.gov` |
| Schedule | Weekly |
| Batch size | `10` (documents per batch) |

---

## Model Deployments

Deployed automatically by `bootstrap.ps1` onto the AI Services resource:

| Deployment Name | Model | SKU | Capacity (TPM) | Purpose |
|-----------------|-------|-----|-----------------|---------|
| `gpt-4o` | GPT-4o 2024-08-06 | GlobalStandard | 30,000 | Agent chat responses |
| `text-embedding-3-small` | text-embedding-3-small | Standard | 120,000 | Document vectorization |

---

## System Prompt

The system prompt lives in
[`foundry/prompts/system-prompt.md`](https://github.com/ricardo-msft-SE/policybot1/blob/main/foundry/prompts/system-prompt.md).
Paste its contents (excluding the first `#` heading line) into the Foundry portal when creating the agent.

Key behaviors enforced by the prompt:

| Rule | Behavior |
|------|----------|
| Scope restriction | Only answers questions about ORC Title 45 |
| Grounding | Only uses information from search results |
| Citation | Every factual claim must include an exact quote + URL |
| Uncertainty | Explicitly says "I couldn't find" rather than guessing |

---

## Scripted Alternative (Advanced)

If you prefer not to use the portal for search configuration, the following scripts provide
a scripted path:

| Script | Purpose |
|--------|---------|
| `scripts/configure-search.py` | Creates the AI Search index schema via Python SDK |
| `scripts/configure-crawler.ps1` | Sets up the web crawler data source and indexer via REST API |

Run them after `bootstrap.ps1`:

```powershell
# Set env vars from bootstrap.ps1 output, then:
python scripts/configure-search.py create-index

.\scripts\configure-crawler.ps1 `
  -ResourceGroupName "rg-policybot" `
  -SearchServiceName "search-policybot-XXXX" `
  -IndexName "ohio-title45-index" `
  -SeedUrl "https://codes.ohio.gov/ohio-revised-code/title-45" `
  -CrawlDepth 10
```
