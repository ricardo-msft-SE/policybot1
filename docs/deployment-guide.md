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

## Step 3 — Create the Foundry Agents

The system uses **five agents**: four specialists and one Orchestrator. Create the specialists
first — the Orchestrator must connect to them as tools, so they must exist first.

> **Open:** [ai.azure.com](https://ai.azure.com) → Project **`policybot-project`** → **Agents** → **New agent**

### 3a. Definitions Agent

| Field | Value |
|-------|-------|
| Name | `definitions-agent` |
| Model | `gpt-4o` |
| Temperature | `0` |

In the **Instructions** box, paste the full contents of
[`foundry/prompts/definitions-agent-prompt.md`](https://github.com/ricardo-msft-SE/policybot1/blob/main/foundry/prompts/definitions-agent-prompt.md).

Under **Knowledge** → **Add** → **Azure AI Search**:

| Field | Value |
|-------|-------|
| Connection | `aisearch-conn` |
| Index | `ohio-title45-index` |
| Search type | `Hybrid (vector + keyword)` |
| Semantic ranker | Enabled — `policy-semantic-config` |
| Top K | `10` |
| Strictness | `4` |
| In scope only | ✅ Enabled |

Click **Save**. Copy the agent ID — you will need it for the Orchestrator.

---

### 3b. Traffic & Violations Agent

| Field | Value |
|-------|-------|
| Name | `traffic-violations-agent` |
| Model | `gpt-4o` |
| Temperature | `0` |

Paste [`foundry/prompts/traffic-violations-agent-prompt.md`](https://github.com/ricardo-msft-SE/policybot1/blob/main/foundry/prompts/traffic-violations-agent-prompt.md)
into the Instructions box. Apply the same Knowledge settings as Step 3a. Click **Save**.

---

### 3c. Licensing & Registration Agent

| Field | Value |
|-------|-------|
| Name | `licensing-agent` |
| Model | `gpt-4o-mini` |
| Temperature | `0.1` |

Paste [`foundry/prompts/licensing-agent-prompt.md`](https://github.com/ricardo-msft-SE/policybot1/blob/main/foundry/prompts/licensing-agent-prompt.md)
into the Instructions box. Apply the same Knowledge settings. Click **Save**.

---

### 3d. Legal Reasoning Agent

| Field | Value |
|-------|-------|
| Name | `legal-reasoning-agent` |
| Model | `o3-mini` |
| Temperature | `1` ⚠️ required for reasoning models |
| Max tokens | `8192` (reasoning uses more tokens) |

Paste [`foundry/prompts/legal-reasoning-agent-prompt.md`](https://github.com/ricardo-msft-SE/policybot1/blob/main/foundry/prompts/legal-reasoning-agent-prompt.md)
into the Instructions box. Apply the same Knowledge settings. Click **Save**.

{: .warning }
`o3-mini` **requires temperature=1**. Setting it to 0 will cause API errors. Do not set
`topP` or `frequencyPenalty` for o3-mini — they are not supported on reasoning models.

---

### 3e. Orchestrator Agent (create last)

| Field | Value |
|-------|-------|
| Name | `orchestrator` |
| Model | `gpt-4o` |
| Temperature | `0.1` |

Paste [`foundry/prompts/orchestrator-prompt.md`](https://github.com/ricardo-msft-SE/policybot1/blob/main/foundry/prompts/orchestrator-prompt.md)
into the Instructions box. Apply the same Knowledge settings.

**Connect the four specialists as tools:**

1. Click **"Add a tool"** → **"Agent"**
2. Select `definitions-agent` → Tool name: `definitions-agent`
3. Repeat for `traffic-violations-agent`, `licensing-agent`, `legal-reasoning-agent`

Your tool list should look like:

| Tool name | Agent |
|-----------|-------|
| `definitions-agent` | Definitions Agent |
| `traffic-violations-agent` | Traffic & Violations Agent |
| `licensing-agent` | Licensing & Registration Agent |
| `legal-reasoning-agent` | Legal Reasoning Agent |

Click **Save**.

---

## Step 4 — Test in the Playground

Open the **`orchestrator`** agent and click **"Try in playground"**.
Test with these sample questions:

| Question | Expected routing + behavior |
|----------|-----------------------------|
| *"What is the legal definition of a vehicle in Ohio?"* | → Definitions Agent → verbatim ORC § 4501.01 quote |
| *"What are the penalties for OVI (drunk driving)?"* | → Traffic & Violations Agent → penalty table from ORC § 4511.19 |
| *"How do I renew my driver's license in Ohio?"* | → Licensing Agent → numbered steps with ORC § 4507.x citations |
| *"My license expired 2 weeks ago. Am I still allowed to drive to the BMV to renew?"* | → Legal Reasoning Agent → step-by-step analysis + conclusion + disclaimer |
| *"What is the capital of France?"* | Orchestrator scope refusal — no routing |
| *"What does Title 1 of the ORC say?"* | Orchestrator out-of-scope refusal |

**Signs the multi-agent system is configured correctly:**
- ✅ The Orchestrator invokes a specialist tool (visible in the "activity" or "trace" panel)
- ✅ Responses include exact quotes and `codes.ohio.gov` source URLs
- ✅ Off-topic questions are declined without routing to any specialist
- ✅ o3-mini responses include a visible reasoning chain before the conclusion

If the Orchestrator answers directly without calling a tool, verify the connected agents are
added and the orchestrator system prompt is fully pasted.

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
| Orchestrator answers without calling a tool | Specialists not connected | Re-add connected agents in Orchestrator config |
| `o3-mini` returns API error about temperature | Temperature not set to 1 | Set temperature=1; remove `topP` and `frequencyPenalty` |
| Legal Reasoning Agent gives no answer | Max tokens too low for reasoning | Set max tokens to 8192 or higher |
