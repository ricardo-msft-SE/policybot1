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

## AI Search Strategy for this Use Case

For this policy/legal assistant, AI Search is the production grounding baseline.

Why this is emphasized:

- legal responses require strict scope control
- citation quality depends on stable metadata fields
- workflow routing quality improves with deterministic retrieval behavior
- evaluation/regression reliability requires consistent retrieval patterns

Primary profile:

| Setting | Recommended value | Outcome |
|--------|-------------------|---------|
| `knowledge.queryType` | `vector_semantic_hybrid` | Balanced recall + precision |
| `knowledge.strictness` | `4` | Limits unsupported responses |
| `knowledge.topK` | `10` | Adequate legal context window |
| `knowledge.inScope` | `true` | Enforces Title 45 boundary |
| `knowledge.semanticConfiguration` | `policy-semantic-config` | Better statutory relevance |

See [Appendix - AI Search vs Bing Custom Grounding]({{ site.baseurl }}/appendix-ai-search-vs-bing-grounding)
for alternative grounding trade-offs.

---

## Infrastructure (`scripts/bootstrap.ps1` Parameters)

| Parameter | Default | Description |
|-----------|---------|-------------|
| `SubscriptionId` | `{YOUR_SUBSCRIPTION_ID}` | Azure subscription (`az account show --query id`) |
| `ResourceGroupName` | `rg-policybot` | Resource group to deploy into |
| `Location` | `eastus2` | Azure region |
| `HubName` | `policybot-hub` | Optional compatibility parameter; Project is primary |
| `ProjectName` | `policybot-project` | Foundry Project name |
| `-InstallPackages` | *(switch)* | Installs Python dependencies before running |
| `-SkipInfra` | *(switch)* | Skips Bicep deployment (re-runs connections only) |
| `-SkipIndexing` | *(switch)* | Skips scraper call (if any) |
| `-WhatIf` | *(switch)* | Dry run — prints what would happen, creates nothing |

---

## Agent Settings (`foundry/agent-config.json`)

This file is a **configuration reference** — the actual workflow and agents are created in
the Foundry portal.

| Setting | Value | Notes |
|---------|-------|-------|
| `workflow.scopeGuard.enabled` | `true` | Reject out-of-scope prompts before routing |
| `workflow.intentClassifier.enabled` | `true` | Route between legal reference and BMV FAQ |
| `workflow.confidenceThreshold` | `0.75` (recommended start) | Below threshold triggers clarification |
| `workflow.maxClarificationTurns` | `2` | Prevent infinite clarification loops |
| `agents.legalReference.model` | `gpt-4o` | Primary legal/statutory route |
| `agents.bmvFaq.model` | `gpt-4o-mini` | Secondary procedural route |
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

Detailed setup steps live in [Deployment Guide Step 3]({{ site.baseurl }}/deployment-guide#step-3--index-ohio-revised-code-title-45).

Use this section as a value reference for tuning after initial deployment.

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
| `gpt-4o` | GPT-4o 2024-08-06 | GlobalStandard | 30,000 | Workflow and legal reference route |
| `gpt-4o-mini` | GPT-4o-mini | GlobalStandard | 30,000 | BMV FAQ route |
| `text-embedding-3-small` | text-embedding-3-small | Standard | 120,000 | Document vectorization |

---

## Backend API Boundary Settings

Recommended backend configuration:

| Setting | Value | Purpose |
|---------|-------|---------|
| Managed Identity | Enabled | Secure Foundry invocation |
| Input validation | Enabled | Block malformed or abusive prompts |
| Request logging | Enabled | Trace request lifecycle |
| Response metadata | Include route and clarification flags | Support observability and debugging |

---

## Prompt and Workflow Logic

Prompt files contain domain behavior. Routing behavior lives in workflow nodes.

Key behavior split:

| Rule | Behavior |
|------|----------|
| Scope restriction | Scope guard node rejects non-Title 45 prompts |
| Clarification loop | Workflow asks follow-up questions under low confidence |
| Routing decision | Workflow routes to legal reference or BMV FAQ agent |
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
