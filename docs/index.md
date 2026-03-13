---
layout: default
title: Home
nav_order: 1
description: "AI chatbot for Ohio Revised Code Title 45, built on Microsoft Azure AI Foundry"
permalink: /
---

# Ohio ORC Title 45 Policy Bot
{: .fs-9 }

An AI chatbot that answers questions **exclusively** from Ohio Revised Code Title 45 (Motor Vehicles),
powered by Microsoft Azure AI Foundry — with no custom application code required.
{: .fs-6 .fw-300 }

[Deploy Now]({{ site.baseurl }}/deployment-guide){: .btn .btn-primary .fs-5 .mb-4 .mb-md-0 .mr-2 }
[View Architecture]({{ site.baseurl }}/architecture){: .btn .fs-5 .mb-4 .mb-md-0 }

---

## What Is This?

The Ohio ORC Title 45 Policy Bot is an AI assistant that:

- **Only answers from official sources** — every response is grounded in [codes.ohio.gov/ohio-revised-code/title-45](https://codes.ohio.gov/ohio-revised-code/title-45)
- **Cites exact sections** — you get quotes and source URLs, not unsourced summaries
- **Refuses to guess** — if the answer is not in the indexed code, the bot says so
- **Runs entirely on Azure** — your data stays within your subscription

## Design Philosophy

> This project intentionally avoids custom application code. Microsoft Foundry's portal
> handles agent creation, knowledge source configuration, and web app deployment. The
> only automation is the initial Azure infrastructure provisioning (`bootstrap.ps1`).

## Architecture at a Glance

| Component | Azure Service | How It's Configured |
|-----------|--------------|---------------------|
| AI Agent | Azure AI Foundry | Foundry portal |
| Language Model | Azure OpenAI GPT-4o | Foundry portal |
| Knowledge Base | Azure AI Search | Portal "Import and vectorize data" wizard |
| Web Crawler | AI Search Indexer | Portal — scheduled weekly |
| Chat Web App | Azure App Service | Foundry "Deploy as web app" button |
| Monitoring | Application Insights | Deployed via Bicep |

## Quick Start

```powershell
# 1. Clone the repo
git clone https://github.com/ricardo-msft-SE/policybot1.git
cd policybot1

# 2. Deploy Azure infrastructure (~10 min)
az login
.\scripts\bootstrap.ps1
```

Then follow the [Deployment Guide]({{ site.baseurl }}/deployment-guide) for the portal steps (Steps 2-5).

---

## Documentation

| Page | Contents |
|------|---------|
| [Architecture]({{ site.baseurl }}/architecture) | Component design, data flow, infrastructure layout |
| [Deployment Guide]({{ site.baseurl }}/deployment-guide) | Step-by-step portal walkthrough |
| [Configuration Reference]({{ site.baseurl }}/configuration) | All tuneable settings |
| [Evaluation Guide]({{ site.baseurl }}/evaluation-guide) | Testing accuracy and groundedness |
| [Cost Estimation]({{ site.baseurl }}/cost-estimation) | Azure pricing for internal and public scenarios |
| [Pain Points Addressed]({{ site.baseurl }}/pain-points-addressed) | Deep search, hallucination, and citation design |
