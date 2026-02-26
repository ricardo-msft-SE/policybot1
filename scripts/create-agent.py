"""
Policy Bot Agent Creation Script
Creates the Policy Bot agent programmatically using Azure AI Projects SDK

Usage:
    Set environment variables:
        AZURE_AI_PROJECT_ENDPOINT - Your Foundry project endpoint
        AZURE_SEARCH_ENDPOINT     - Your Azure AI Search endpoint
        AZURE_SEARCH_INDEX        - Index name (default: policy-index)
        AZURE_OPENAI_DEPLOYMENT   - Model deployment (default: gpt-4o)

    Run:
        python scripts/create-agent.py

Prerequisites:
    pip install azure-ai-projects azure-identity
    az login
"""

import os
import sys
from pathlib import Path

try:
    from azure.identity import DefaultAzureCredential
    from azure.ai.projects import AIProjectClient
    from azure.ai.projects.models import (
        AzureAISearchTool,
        AzureAISearchToolParameters,
    )
except ImportError:
    print("❌ Required packages not installed. Run:")
    print("   pip install azure-ai-projects azure-identity")
    sys.exit(1)


# Configuration from environment variables
PROJECT_ENDPOINT = os.environ.get("AZURE_AI_PROJECT_ENDPOINT")
SEARCH_SERVICE_ENDPOINT = os.environ.get("AZURE_SEARCH_ENDPOINT")
SEARCH_INDEX_NAME = os.environ.get("AZURE_SEARCH_INDEX", "policy-index")
MODEL_DEPLOYMENT = os.environ.get("AZURE_OPENAI_DEPLOYMENT", "gpt-4o")

# Load system prompt from file or use embedded version
SCRIPT_DIR = Path(__file__).parent
PROMPT_FILE = SCRIPT_DIR.parent / "foundry" / "prompts" / "system-prompt.md"

if PROMPT_FILE.exists():
    with open(PROMPT_FILE, "r", encoding="utf-8") as f:
        # Skip the title line if present
        content = f.read()
        if content.startswith("# "):
            content = "\n".join(content.split("\n")[1:])
        SYSTEM_PROMPT = content.strip()
else:
    SYSTEM_PROMPT = """You are Policy Bot, an expert assistant for government policy research.

## Core Rules

1. **ONLY use information from the provided search results**
2. **NEVER make up or assume policy information**
3. **Always cite your sources with exact quotes**

## Citation Format

For every claim, include:
- The exact quote from the source
- The source URL
- The relevant section/title

Example response format:

According to Ohio Revised Code Section 4511.01:
> "Vehicle means every device, including a motorized bicycle and 
> an electric bicycle, in, upon, or by which any person or property 
> may be transported..."

Source: https://codes.ohio.gov/ohio-revised-code/section-4511.01

## When You Don't Know

If the search results don't contain relevant information, say:
"I couldn't find specific information about [topic] in the indexed 
policy documents. Please try rephrasing your question or verify 
this topic is covered in the Ohio Revised Code."
"""


def validate_config():
    """Validate required environment variables are set."""
    missing = []
    
    if not PROJECT_ENDPOINT:
        missing.append("AZURE_AI_PROJECT_ENDPOINT")
    if not SEARCH_SERVICE_ENDPOINT:
        missing.append("AZURE_SEARCH_ENDPOINT")
    
    if missing:
        print("❌ Missing required environment variables:")
        for var in missing:
            print(f"   - {var}")
        print("\nSet them using:")
        print('   $env:AZURE_AI_PROJECT_ENDPOINT = "https://your-resource.services.ai.azure.com/api/projects/policybot"')
        print('   $env:AZURE_SEARCH_ENDPOINT = "https://your-search.search.windows.net"')
        sys.exit(1)
    
    print("✅ Configuration validated")
    print(f"   Project: {PROJECT_ENDPOINT}")
    print(f"   Search:  {SEARCH_SERVICE_ENDPOINT}")
    print(f"   Index:   {SEARCH_INDEX_NAME}")
    print(f"   Model:   {MODEL_DEPLOYMENT}")


def create_policy_bot_agent():
    """Create the Policy Bot agent with Azure AI Search integration."""
    
    # Authenticate using DefaultAzureCredential
    credential = DefaultAzureCredential()
    
    # Initialize the AI Project client
    client = AIProjectClient(
        endpoint=PROJECT_ENDPOINT,
        credential=credential
    )
    
    # Configure Azure AI Search as a knowledge source
    search_tool = AzureAISearchTool(
        parameters=AzureAISearchToolParameters(
            index_connection_id=f"{SEARCH_SERVICE_ENDPOINT}/indexes/{SEARCH_INDEX_NAME}",
            index_name=SEARCH_INDEX_NAME,
            query_type="vector_semantic_hybrid",
            semantic_configuration="policy-semantic-config",
            top_n=10,
            strictness=3,
            in_scope=True,  # Critical: Only use search results
        )
    )
    
    # Create the agent
    agent = client.agents.create(
        name="policy-bot",
        model=MODEL_DEPLOYMENT,
        instructions=SYSTEM_PROMPT,
        tools=[search_tool],
        temperature=0.1,
        metadata={
            "purpose": "Government policy research assistant",
            "source": "Ohio Revised Code",
            "created_by": "policybot-deployment-script",
            "version": "1.0.0"
        }
    )
    
    print(f"\n✅ Agent created successfully!")
    print(f"   Agent ID: {agent.id}")
    print(f"   Name:     {agent.name}")
    print(f"   Model:    {agent.model}")
    
    return agent


def list_agents():
    """List all agents in the project."""
    credential = DefaultAzureCredential()
    client = AIProjectClient(
        endpoint=PROJECT_ENDPOINT,
        credential=credential
    )
    
    agents = client.agents.list()
    
    print("\n📋 Existing agents:")
    for agent in agents.data:
        print(f"   - {agent.name} ({agent.id})")
    
    return agents


def test_agent(agent_id: str, test_query: str = "What is the legal definition of a vehicle in Ohio?"):
    """Test the created agent with a sample query."""
    
    credential = DefaultAzureCredential()
    client = AIProjectClient(
        endpoint=PROJECT_ENDPOINT,
        credential=credential
    )
    
    # Create a thread for the conversation
    thread = client.agents.threads.create()
    
    # Send test message
    client.agents.messages.create(
        thread_id=thread.id,
        role="user",
        content=test_query
    )
    
    # Run the agent
    run = client.agents.runs.create_and_wait(
        thread_id=thread.id,
        agent_id=agent_id
    )
    
    # Get the response
    messages = client.agents.messages.list(thread_id=thread.id)
    response = messages.data[0].content[0].text.value
    
    print(f"\n📝 Test Query: {test_query}")
    print(f"\n🤖 Agent Response:\n{response}")
    
    # Verify response quality
    has_citation = "Source:" in response or "http" in response
    has_quote = ">" in response or '"' in response
    
    print(f"\n✅ Has citation: {has_citation}")
    print(f"✅ Has quote: {has_quote}")
    
    # Cleanup
    client.agents.threads.delete(thread_id=thread.id)
    
    return response


def delete_agent(agent_id: str):
    """Delete an agent by ID."""
    credential = DefaultAzureCredential()
    client = AIProjectClient(
        endpoint=PROJECT_ENDPOINT,
        credential=credential
    )
    
    client.agents.delete(agent_id=agent_id)
    print(f"✅ Agent {agent_id} deleted")


def main():
    """Main entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(description="Policy Bot Agent Management")
    parser.add_argument("action", choices=["create", "list", "test", "delete"],
                       help="Action to perform")
    parser.add_argument("--agent-id", help="Agent ID (for test/delete)")
    parser.add_argument("--query", help="Test query", 
                       default="What is the legal definition of a vehicle in Ohio?")
    
    args = parser.parse_args()
    
    # Validate configuration
    validate_config()
    
    if args.action == "create":
        agent = create_policy_bot_agent()
        print(f"\n💡 To test the agent, run:")
        print(f"   python scripts/create-agent.py test --agent-id {agent.id}")
        
    elif args.action == "list":
        list_agents()
        
    elif args.action == "test":
        if not args.agent_id:
            print("❌ --agent-id required for test action")
            sys.exit(1)
        test_agent(args.agent_id, args.query)
        
    elif args.action == "delete":
        if not args.agent_id:
            print("❌ --agent-id required for delete action")
            sys.exit(1)
        delete_agent(args.agent_id)


if __name__ == "__main__":
    if len(sys.argv) == 1:
        # Default action: create
        validate_config()
        agent = create_policy_bot_agent()
        
        print("\n" + "=" * 50)
        print("Testing agent...")
        print("=" * 50)
        test_agent(agent.id)
    else:
        main()
