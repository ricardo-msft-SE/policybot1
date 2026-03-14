---
layout: default
title: Deployment Guide
nav_order: 4
---

# Deployment Guide
{: .no_toc }

Deployment follows a **backend API plus Foundry workflow** pattern. After infrastructure deploys,
configure backend API integration, index grounding data, create two domain agents, and wire the
workflow router.

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
- Baseline services used by backend API and workflow orchestration

When it finishes, the script prints a **configuration summary** with endpoints — keep this
window open for the next steps.

{: .note }
To skip infrastructure if already deployed: `.\scripts\bootstrap.ps1 -SkipInfra`

---

## Step 2 — Deploy Backend API Layer

Deploy or configure the backend API as the orchestration and security boundary.

Required backend responsibilities:

- Receive prompt payload from UI
- Validate and sanitize request data
- Authenticate to Foundry using Managed Identity
- Invoke the workflow endpoint
- Return normalized response with citations and routing metadata
- Emit telemetry to Application Insights

Recommended endpoint contract:

```json
POST /api/chat
{
   "question": "string",
   "sessionId": "string",
   "userId": "string"
}
```

```json
200 OK
{
   "answer": "string",
   "citations": [],
   "routeType": "legal_reference|bmv_faq",
   "clarificationAsked": true
}
```

{: .warning }
Keep AI logic in Foundry workflow and domain agents. The backend API should not perform
legal reasoning.

---

## Step 3 — Index Ohio Revised Code Title 45

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

## Step 4 — Create the Foundry Domain Agents

Create two domain agents first. The workflow router references these agents.

> **Open:** [ai.azure.com](https://ai.azure.com) → Project **`policybot-project`** → **Agents** → **New agent**

### 4a. Primary Agent — Legal Reference

| Field | Value |
|-------|-------|
| Name | `legal-reference-agent` |
| Model | `gpt-4o` |
| Temperature | `0.1` |

Configure grounding:

| Field | Value |
|-------|-------|
| Connection | `aisearch-conn` |
| Index | `ohio-title45-index` |
| Search type | `Hybrid (vector + keyword)` |
| Semantic ranker | `policy-semantic-config` |
| Top K | `10` |
| Strictness | `4` |
| In scope only | ✅ Enabled |

### 4b. Secondary Agent — BMV FAQ

| Field | Value |
|-------|-------|
| Name | `bmv-faq-agent` |
| Model | `gpt-4o-mini` |
| Temperature | `0.1` |

Use BMV operational content and policy FAQ material for this agent's knowledge source.

---

## Step 5 — Configure Foundry Workflow Router

Configure the orchestration workflow with these nodes:

1. **Scope guard**: reject non-Title 45 prompts
2. **Intent classifier**: classify legal reference vs BMV FAQ
3. **Confidence decision**: high confidence routes immediately
4. **Clarification question node**: low confidence asks follow-up question
5. **Reclassification node**: process clarification answer
6. **Agent invoke node**: call `legal-reference-agent` or `bmv-faq-agent`
7. **Synthesis and citation check node**: ensure grounded response format

Clarification behavior policy:

- Allow 1 to 2 follow-up questions maximum
- If still ambiguous, route to `legal-reference-agent` with explicit uncertainty
- Preserve citations and route metadata in final payload

---

## Step 6 — Test in the Playground and API

Test both workflow behavior and backend API behavior.

Open the workflow entry point and click **"Try in playground"**.
Test with these sample questions:

| Question | Expected routing + behavior |
|----------|-----------------------------|
| *"What does ORC say about OVI penalties?"* | Route to `legal-reference-agent` |
| *"How do I renew my license at BMV?"* | Route to `bmv-faq-agent` |
| *"Can you help me with this driving issue?"* | Clarification question asked before routing |
| *"What is the capital of France?"* | Scope refusal |

**Signs the workflow system is configured correctly:**
- ✅ Workflow shows node-by-node route decisions in trace/activity
- ✅ Low-confidence prompts trigger follow-up clarification question
- ✅ Follow-up response causes reclassification and final route selection
- ✅ Responses include exact quotes and `codes.ohio.gov` source URLs
- ✅ Off-topic questions are declined before agent invocation

Also test the backend endpoint directly and confirm route metadata is present in payload.

---

## Step 7 — Deploy or Integrate Client UI

1. Configure the UI to call backend endpoint `POST /api/chat`
2. Ensure no Foundry credentials are present in client code
3. Verify UI can render:

   - Answer text
   - Citations and source URLs
   - Clarification prompts from workflow

Optional: deploy Foundry-provided web app for demonstration environments.

---

## Step 8 — Enable Observability

In Application Insights, track:

- request count and latency by route type
- clarification question rate
- out-of-scope refusal rate
- citation completeness failures
- workflow node errors

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
| Backend API returns 401 to Foundry | Managed Identity or RBAC missing | Reconfigure identity and role assignments |
| Clarification never appears | Confidence threshold too low | Increase threshold in workflow decision node |
| Workflow always asks follow-up | Threshold too high | Lower threshold and retest with sample prompts |
| Indexer shows 0 documents | Site blocked portal crawler | Use `configure-crawler.ps1` script alternative |
| `bootstrap.ps1` fails at model deployment | TPM quota limit | Reduce capacity or switch `Location` to another region |
| Agent not found in Foundry portal | Wrong project selected | Ensure `policybot-project` is selected |
| `az ml workspace create` fails on hub-less | Old az ml extension | Run `az extension update --name ml` |
| Wrong route selected | Classifier prompt or examples insufficient | Add classifier examples and retest |
