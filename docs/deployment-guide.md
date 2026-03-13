---
layout: default
title: Deployment Guide
nav_order: 3
---

# Deployment Guide
{: .no_toc }

Portal-first approach. After the infrastructure script runs (~10 min), the remaining
steps are portal clicks — no SDK code required.

## Table of contents
{: .no_toc .text-delta }

1. TOC
{:toc}

---

## Prerequisites

| Requirement | How to Verify |
|-------------|---------------|
| Azure subscription (Contributor role) | `az account show` |
| Azure CLI installed | `az --version` |
| PowerShell 7+ | `$PSVersionTable.PSVersion` |
| Subscription ID | `ee0073ce-de38-45ed-a940-4dbfd9435dc1` |

---

## Step 1 — Deploy Azure Infrastructure

This is the only automated step. It deploys all Azure resources and creates the Foundry
Project (hub-less — the new Azure AI Foundry model).

```powershell
# From the repo root
git clone https://github.com/ricardo-msft-SE/policybot1.git
cd policybot1

az login
.\scripts\bootstrap.ps1
```

What `bootstrap.ps1` creates:

- Resource group `rg-policybot` in `eastus2`
- Azure AI Services with `gpt-4o` and `text-embedding-3-small` deployments
- Azure AI Search (Basic SKU)
- Application Insights + Log Analytics workspace
- **Foundry Project** (`policybot-project`) linked directly to AI Services — no Hub workspace required
- AI Search connection (`aisearch-conn`) registered on the Project

When it finishes, the script prints a **configuration summary** with endpoints — keep this
window open for the next steps.

{: .note }
To skip infrastructure if already deployed: `.\scripts\bootstrap.ps1 -SkipInfra`

---

## Step 2 — Index Ohio Revised Code Title 45

Use the Azure AI Search portal wizard to crawl and vectorize Title 45. No scraper code needed.

1. Open [portal.azure.com](https://portal.azure.com) and navigate to your **AI Search** resource (`search-policybot-*`)
2. Click **"Import and vectorize data"**
3. **Data source**: Select **Web** → enter seed URL:
   ```
   https://codes.ohio.gov/ohio-revised-code/title-45
   ```
4. **Parsing mode**: HTML
5. **Crawler settings**: Depth = `10`, include subpages ✅
6. **Vectorize text**: Select your **AI Services** resource → deployment `text-embedding-3-small`
7. **Index name**: `ohio-title45-index`
8. **Semantic configuration name**: `policy-semantic-config`
9. Click **Create**

The indexer runs immediately. Expect **10–30 minutes** for the full site crawl.

**Verify:** AI Search resource → **Indexers** → `ohio-title45-indexer` → document count should be > 0.

{: .note }
To schedule automatic weekly re-indexing: open the indexer → **Settings** → **Schedule** → Weekly.

### Alternative (Scripted)

If the portal wizard is unavailable or the site blocks the portal crawler, use the provided scripts:

```powershell
# Set environment variables printed by bootstrap.ps1, then:
python scripts\configure-search.py create-index

.\scripts\configure-crawler.ps1 `
  -ResourceGroupName "rg-policybot" `
  -SearchServiceName "search-policybot-XXXX" `
  -IndexName "ohio-title45-index" `
  -SeedUrl "https://codes.ohio.gov/ohio-revised-code/title-45" `
  -CrawlDepth 10
```

---

## Step 3 — Create the Foundry Agent

1. Go to [ai.azure.com](https://ai.azure.com)
2. Select your project **`policybot-project`**
3. Navigate to **Agents** → **New agent**
4. Fill in the agent settings:

   | Field | Value |
   |-------|-------|
   | Name | `ohio-title45-bot` |
   | Model | `gpt-4o` |
   | Temperature | `0.1` |

5. In the **Instructions** box, paste the full contents of
   [`foundry/prompts/system-prompt.md`](https://github.com/ricardo-msft-SE/policybot1/blob/main/foundry/prompts/system-prompt.md)
   (skip the first `#` heading line)

6. Under **Knowledge** → **Add** → **Azure AI Search**, configure:

   | Field | Value |
   |-------|-------|
   | Connection | `aisearch-conn` |
   | Index | `ohio-title45-index` |
   | Search type | `Hybrid (vector + keyword)` |
   | Semantic ranker | Enabled — config: `policy-semantic-config` |
   | Top K | `10` |
   | Strictness | `4` |
   | In scope only | ✅ Enabled |

7. Click **Save**

---

## Step 4 — Test in the Playground

1. In the Foundry portal, open your agent and click **"Try in playground"**
2. Test with these sample questions:

   | Question | Expected behavior |
   |----------|------------------|
   | *"What is the legal definition of a vehicle in Ohio?"* | Quote from ORC 4501.01 with URL |
   | *"What are the penalties for OVI (drunk driving)?"* | Quote from ORC 4511.19 with URL |
   | *"What is the capital of France?"* | Scope refusal message |
   | *"What does Title 1 of the ORC say?"* | Out-of-scope refusal message |

**Signs the agent is configured correctly:**
- ✅ Responses include exact quotes and `codes.ohio.gov` source URLs
- ✅ Off-topic questions are declined with the configured refusal message
- ✅ Answers for questions outside the indexed content say "I couldn't find"

If answers are drawing on general knowledge (no citations), increase **Strictness** or verify
the `In scope only` toggle is enabled.

---

## Step 5 — Deploy the Chat Web App

1. From the Chat Playground, click **"Deploy"** → **"As a web app"**
2. Configure:

   | Field | Value |
   |-------|-------|
   | Subscription | `ee0073ce-de38-45ed-a940-4dbfd9435dc1` |
   | Resource group | `rg-policybot` |
   | App name | `policybot-webapp` |
   | Pricing plan | F1 for testing / B1 for production |

3. Click **Deploy** — takes about 3 minutes
4. Once deployed, the portal shows the web app URL

Share the URL (`https://policybot-webapp.azurewebsites.net`) with users.

---

## Keeping the Knowledge Base Current

When codes.ohio.gov publishes updates to Title 45:

1. Go to AI Search → **Indexers** → `ohio-title45-indexer`
2. Click **Run** to trigger an immediate re-crawl

If weekly scheduling is configured in Step 2, this happens automatically.

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| Agent answers from general knowledge (no citations) | `In scope only` is off | Re-check knowledge source settings |
| "I couldn't find" for valid Title 45 questions | Index not populated | Check indexer status; wait for crawl to finish |
| Web app returns 503 | App Service cold start (F1 tier) | Wait 30 seconds and refresh |
| Indexer shows 0 documents | Site blocked portal crawler | Use `configure-crawler.ps1` script alternative |
| `bootstrap.ps1` fails at model deployment | TPM quota limit | Reduce capacity or switch `Location` to another region |
| Agent not found in Foundry portal | Wrong project selected | Ensure `policybot-project` is selected |
| `az ml workspace create` fails on hub-less | Old az ml extension | Run `az extension update --name ml` |
