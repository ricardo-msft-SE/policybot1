# Ohio ORC Title 45 Policy Bot

An AI chatbot that answers questions **exclusively** from
[Ohio Revised Code Title 45 (Motor Vehicles)](https://codes.ohio.gov/ohio-revised-code/title-45),
powered by Microsoft Azure AI Foundry.

📖 **[Full Documentation](https://ricardo-msft-SE.github.io/policybot1)**

---

## What It Does

- Answers questions grounded in official Ohio law (Title 45 only)
- Cites exact section numbers and quotes with source URLs
- Refuses to answer out-of-scope questions (other titles, general knowledge)
- Runs entirely within your Azure subscription

## Architecture

```
codes.ohio.gov/title-45
        │ (weekly crawl, AI Search portal wizard)
        ▼
Azure AI Search (ohio-title45-index)
        │ (vector + semantic hybrid retrieval, top 10 chunks, strictness 4)
        ▼
Azure AI Foundry Agent (GPT-4o, in_scope=true)
        │
        ▼
Chat Web App (deployed from Foundry portal — Microsoft-maintained UI)
```

## Deployment

**Step 1 — Deploy infrastructure** (~10 min, automated):

```powershell
az login
.\scripts\bootstrap.ps1
```

**Steps 2–5 — Portal configuration** (no code):

1. Index Title 45 via AI Search **"Import and vectorize data"** wizard
2. Create agent in Foundry portal (paste system prompt, add AI Search knowledge source)
3. Test in Chat Playground
4. Click **Deploy → As a web app**

→ [Full deployment guide](https://ricardo-msft-SE.github.io/policybot1/deployment-guide)

## Repository Structure

```
infra/                    ← Bicep templates (AI Search, OpenAI, App Insights)
scripts/
  bootstrap.ps1           ← End-to-end infrastructure automation
  configure-search.py     ← AI Search index schema (scripted alternative to portal)
  configure-crawler.ps1   ← Web crawler setup (scripted alternative to portal)
foundry/
  agent-config.json       ← Agent configuration reference (values to enter in portal)
  prompts/
    system-prompt.md      ← Paste into Foundry portal when creating the agent
docs/                     ← GitHub Pages documentation (Jekyll / just-the-docs)
```

## Key Design Decision

This project uses Microsoft Foundry's built-in portal capabilities rather than custom
SDK code. The portal handles agent creation, knowledge source configuration, and web app
deployment. The only automation script is `bootstrap.ps1` for initial Azure infrastructure.

## License

MIT
