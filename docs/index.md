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
powered by Microsoft Azure AI Foundry with a backend API security boundary.
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
- **Uses backend API orchestration** — the UI calls backend API only; no direct client-to-Foundry credentials

## Design Philosophy

> The reference design uses a backend API security boundary plus a Foundry workflow
> router. The workflow can ask follow-up clarification questions before selecting the
> final domain agent route.

## Architecture at a Glance

| Component | Azure Service | How It's Configured |
|-----------|--------------|---------------------|
| Backend API | App Service or AKS | Service endpoint managed by DPS |
| Workflow Router | Azure AI Foundry | Foundry workflow nodes |
| Domain Agents | Azure AI Foundry | Two agents: Legal Reference and BMV FAQ |
| Language Models | Azure OpenAI GPT-4o and GPT-4o-mini | Foundry portal |
| Knowledge Base | Azure AI Search | Portal "Import and vectorize data" wizard |
| Web Crawler | AI Search Indexer | Portal — scheduled weekly |
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

Then follow the [Deployment Guide]({{ site.baseurl }}/deployment-guide) for backend + workflow setup.

---

## Documentation

| Page | Contents |
|------|---------|
| [Workflow Architecture]({{ site.baseurl }}/workflow-architecture-alternative) | Primary workflow orchestration design with clarification-question routing |
| [Architecture]({{ site.baseurl }}/architecture) | Component design, data flow, infrastructure layout |
| [Deployment Guide]({{ site.baseurl }}/deployment-guide) | Step-by-step portal walkthrough |
| [Configuration Reference]({{ site.baseurl }}/configuration) | All tuneable settings |
| [Evaluation Guide]({{ site.baseurl }}/evaluation-guide) | Testing accuracy and groundedness |
| [Cost Estimation]({{ site.baseurl }}/cost-estimation) | Azure pricing for internal and public scenarios |
| [Pain Points Addressed]({{ site.baseurl }}/pain-points-addressed) | Deep search, hallucination, and citation design |
