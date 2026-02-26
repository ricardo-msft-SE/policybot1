"""
Azure AI Search Configuration Script
Configures the search index, data source, skillset, and indexer for Policy Bot

Usage:
    Set environment variables:
        AZURE_SEARCH_ENDPOINT  - Your Azure AI Search endpoint
        AZURE_SEARCH_ADMIN_KEY - Admin key (optional if using DefaultAzureCredential)
        AZURE_OPENAI_ENDPOINT  - Your Azure OpenAI endpoint
        CRAWL_URL              - URL to crawl (default: https://codes.ohio.gov/ohio-revised-code)

    Run:
        python scripts/configure-search.py

    Or with explicit action:
        python scripts/configure-search.py create-all
        python scripts/configure-search.py create-index
        python scripts/configure-search.py create-indexer
        python scripts/configure-search.py run-indexer
        python scripts/configure-search.py status

Prerequisites:
    pip install azure-search-documents azure-identity requests
"""

import os
import sys
import json
import time
from typing import Optional

try:
    import requests
    from azure.identity import DefaultAzureCredential
    from azure.core.credentials import AzureKeyCredential
    from azure.search.documents.indexes import SearchIndexClient, SearchIndexerClient
    from azure.search.documents.indexes.models import (
        SearchIndex,
        SearchField,
        SearchFieldDataType,
        VectorSearch,
        HnswAlgorithmConfiguration,
        VectorSearchProfile,
        SemanticConfiguration,
        SemanticField,
        SemanticPrioritizedFields,
        SemanticSearch,
    )
except ImportError as e:
    print(f"❌ Missing required package: {e}")
    print("   Run: pip install azure-search-documents azure-identity requests")
    sys.exit(1)


# Configuration from environment variables
SEARCH_ENDPOINT = os.environ.get("AZURE_SEARCH_ENDPOINT")
SEARCH_ADMIN_KEY = os.environ.get("AZURE_SEARCH_ADMIN_KEY")
OPENAI_ENDPOINT = os.environ.get("AZURE_OPENAI_ENDPOINT")
CRAWL_URL = os.environ.get("CRAWL_URL", "https://codes.ohio.gov/ohio-revised-code")
INDEX_NAME = os.environ.get("AZURE_SEARCH_INDEX", "policy-index")
EMBEDDING_MODEL = os.environ.get("AZURE_EMBEDDING_MODEL", "text-embedding-ada-002")

API_VERSION = "2024-07-01"


def get_credential():
    """Get credential for Azure AI Search."""
    if SEARCH_ADMIN_KEY:
        return AzureKeyCredential(SEARCH_ADMIN_KEY)
    else:
        return DefaultAzureCredential()


def get_headers():
    """Get headers for REST API calls."""
    if SEARCH_ADMIN_KEY:
        return {
            "Content-Type": "application/json",
            "api-key": SEARCH_ADMIN_KEY
        }
    else:
        # Use bearer token from DefaultAzureCredential
        credential = DefaultAzureCredential()
        token = credential.get_token("https://search.azure.com/.default")
        return {
            "Content-Type": "application/json",
            "Authorization": f"Bearer {token.token}"
        }


def validate_config():
    """Validate required environment variables."""
    missing = []
    
    if not SEARCH_ENDPOINT:
        missing.append("AZURE_SEARCH_ENDPOINT")
    if not OPENAI_ENDPOINT:
        missing.append("AZURE_OPENAI_ENDPOINT")
    
    if missing:
        print("❌ Missing required environment variables:")
        for var in missing:
            print(f"   - {var}")
        print("\nSet them using:")
        print('   $env:AZURE_SEARCH_ENDPOINT = "https://your-search.search.windows.net"')
        print('   $env:AZURE_OPENAI_ENDPOINT = "https://your-openai.openai.azure.com"')
        sys.exit(1)
    
    print("✅ Configuration validated")
    print(f"   Search:    {SEARCH_ENDPOINT}")
    print(f"   OpenAI:    {OPENAI_ENDPOINT}")
    print(f"   Index:     {INDEX_NAME}")
    print(f"   Crawl URL: {CRAWL_URL}")


def create_index():
    """Create the search index with vector search and semantic configuration."""
    print("\n📦 Creating search index...")
    
    credential = get_credential()
    client = SearchIndexClient(endpoint=SEARCH_ENDPOINT, credential=credential)
    
    # Define fields
    fields = [
        SearchField(name="id", type=SearchFieldDataType.String, key=True, retrievable=True),
        SearchField(name="content", type=SearchFieldDataType.String, searchable=True, retrievable=True, analyzer_name="en.microsoft"),
        SearchField(name="title", type=SearchFieldDataType.String, searchable=True, filterable=True, retrievable=True, analyzer_name="en.microsoft"),
        SearchField(name="url", type=SearchFieldDataType.String, filterable=True, retrievable=True),
        SearchField(name="lastModified", type=SearchFieldDataType.DateTimeOffset, filterable=True, sortable=True, retrievable=True),
        SearchField(name="chunk_id", type=SearchFieldDataType.String, filterable=True, retrievable=True),
        SearchField(name="parent_id", type=SearchFieldDataType.String, filterable=True, retrievable=True),
        SearchField(
            name="content_vector",
            type=SearchFieldDataType.Collection(SearchFieldDataType.Single),
            searchable=True,
            retrievable=False,
            vector_search_dimensions=1536,
            vector_search_profile_name="vector-profile"
        ),
    ]
    
    # Vector search configuration
    vector_search = VectorSearch(
        algorithms=[
            HnswAlgorithmConfiguration(
                name="hnsw-config",
                parameters={
                    "metric": "cosine",
                    "m": 4,
                    "efConstruction": 400,
                    "efSearch": 500
                }
            )
        ],
        profiles=[
            VectorSearchProfile(
                name="vector-profile",
                algorithm_configuration_name="hnsw-config"
            )
        ]
    )
    
    # Semantic configuration
    semantic_config = SemanticConfiguration(
        name="policy-semantic-config",
        prioritized_fields=SemanticPrioritizedFields(
            title_field=SemanticField(field_name="title"),
            content_fields=[SemanticField(field_name="content")]
        )
    )
    
    semantic_search = SemanticSearch(configurations=[semantic_config])
    
    # Create the index
    index = SearchIndex(
        name=INDEX_NAME,
        fields=fields,
        vector_search=vector_search,
        semantic_search=semantic_search
    )
    
    result = client.create_or_update_index(index)
    print(f"✅ Index '{result.name}' created/updated successfully")
    return result


def create_data_source():
    """Create the data source for web crawling."""
    print("\n🌐 Creating data source...")
    
    # Note: Web crawler data sources have limited REST API support
    # Full configuration requires Portal for crawl depth settings
    
    url = f"{SEARCH_ENDPOINT}/datasources/policy-datasource?api-version={API_VERSION}"
    
    data_source = {
        "name": "policy-datasource",
        "type": "web",
        "credentials": {"connectionString": None},
        "container": {
            "name": CRAWL_URL,
            "query": None
        }
    }
    
    response = requests.put(url, headers=get_headers(), json=data_source)
    
    if response.status_code in [200, 201]:
        print("✅ Data source 'policy-datasource' created")
        print("⚠️  Note: Configure crawl depth (10) in Azure Portal under:")
        print("    AI Search → Data Sources → policy-datasource → Settings")
    else:
        print(f"⚠️  Data source creation returned: {response.status_code}")
        print(f"   {response.text}")
        print("\n   Web crawler may need Portal configuration.")
    
    return response


def create_skillset():
    """Create the skillset for chunking and embedding."""
    print("\n🧠 Creating skillset...")
    
    url = f"{SEARCH_ENDPOINT}/skillsets/policy-skillset?api-version={API_VERSION}"
    
    skillset = {
        "name": "policy-skillset",
        "description": "Skillset for chunking and embedding policy documents",
        "skills": [
            {
                "@odata.type": "#Microsoft.Skills.Text.SplitSkill",
                "name": "split-skill",
                "description": "Split content into chunks",
                "context": "/document",
                "inputs": [{"name": "text", "source": "/document/content"}],
                "outputs": [{"name": "textItems", "targetName": "chunks"}],
                "textSplitMode": "pages",
                "maximumPageLength": 2000,
                "pageOverlapLength": 200
            },
            {
                "@odata.type": "#Microsoft.Skills.Text.AzureOpenAIEmbeddingSkill",
                "name": "embedding-skill",
                "description": "Generate embeddings for chunks",
                "context": "/document/chunks/*",
                "inputs": [{"name": "text", "source": "/document/chunks/*"}],
                "outputs": [{"name": "embedding", "targetName": "content_vector"}],
                "resourceUri": OPENAI_ENDPOINT,
                "deploymentId": EMBEDDING_MODEL,
                "modelName": EMBEDDING_MODEL
            }
        ]
    }
    
    response = requests.put(url, headers=get_headers(), json=skillset)
    
    if response.status_code in [200, 201]:
        print("✅ Skillset 'policy-skillset' created")
    else:
        print(f"❌ Skillset creation failed: {response.status_code}")
        print(f"   {response.text}")
    
    return response


def create_indexer():
    """Create the indexer."""
    print("\n📥 Creating indexer...")
    
    url = f"{SEARCH_ENDPOINT}/indexers/policy-indexer?api-version={API_VERSION}"
    
    indexer = {
        "name": "policy-indexer",
        "dataSourceName": "policy-datasource",
        "targetIndexName": INDEX_NAME,
        "skillsetName": "policy-skillset",
        "schedule": {"interval": "P7D"},  # Weekly
        "parameters": {
            "configuration": {
                "dataToExtract": "contentAndMetadata",
                "parsingMode": "default"
            }
        },
        "fieldMappings": [
            {
                "sourceFieldName": "metadata_storage_path",
                "targetFieldName": "id",
                "mappingFunction": {"name": "base64Encode"}
            },
            {
                "sourceFieldName": "metadata_storage_path",
                "targetFieldName": "url"
            }
        ],
        "outputFieldMappings": [
            {
                "sourceFieldName": "/document/chunks/*/content_vector",
                "targetFieldName": "content_vector"
            },
            {
                "sourceFieldName": "/document/chunks/*",
                "targetFieldName": "content"
            }
        ]
    }
    
    response = requests.put(url, headers=get_headers(), json=indexer)
    
    if response.status_code in [200, 201]:
        print("✅ Indexer 'policy-indexer' created")
    else:
        print(f"❌ Indexer creation failed: {response.status_code}")
        print(f"   {response.text}")
    
    return response


def run_indexer():
    """Run the indexer immediately."""
    print("\n▶️ Running indexer...")
    
    url = f"{SEARCH_ENDPOINT}/indexers/policy-indexer/run?api-version={API_VERSION}"
    
    response = requests.post(url, headers=get_headers())
    
    if response.status_code == 202:
        print("✅ Indexer started")
        print("   Use 'python scripts/configure-search.py status' to check progress")
    else:
        print(f"⚠️  Indexer run returned: {response.status_code}")
        print(f"   {response.text}")
    
    return response


def get_indexer_status():
    """Get the current status of the indexer."""
    print("\n📊 Indexer Status")
    print("-" * 40)
    
    url = f"{SEARCH_ENDPOINT}/indexers/policy-indexer/status?api-version={API_VERSION}"
    
    response = requests.get(url, headers=get_headers())
    
    if response.status_code == 200:
        status = response.json()
        last_result = status.get("lastResult", {})
        
        print(f"   Status:     {status.get('status', 'unknown')}")
        print(f"   Last Run:   {last_result.get('endTime', 'N/A')}")
        print(f"   Items:      {last_result.get('itemsProcessed', 0)} processed")
        print(f"   Failed:     {last_result.get('itemsFailed', 0)}")
        print(f"   Result:     {last_result.get('status', 'N/A')}")
        
        errors = last_result.get("errors", [])
        if errors:
            print(f"\n   Errors:")
            for err in errors[:5]:  # Show first 5 errors
                print(f"      - {err.get('message', 'Unknown error')}")
    else:
        print(f"❌ Failed to get status: {response.status_code}")
    
    return response


def get_index_stats():
    """Get index document count and storage size."""
    print("\n📈 Index Statistics")
    print("-" * 40)
    
    url = f"{SEARCH_ENDPOINT}/indexes/{INDEX_NAME}/stats?api-version={API_VERSION}"
    
    response = requests.get(url, headers=get_headers())
    
    if response.status_code == 200:
        stats = response.json()
        doc_count = stats.get("documentCount", 0)
        storage = stats.get("storageSize", 0) / (1024 * 1024)  # Convert to MB
        
        print(f"   Documents:  {doc_count:,}")
        print(f"   Storage:    {storage:.2f} MB")
    else:
        print(f"   Index may not exist yet: {response.status_code}")
    
    return response


def create_all():
    """Create all components: index, data source, skillset, and indexer."""
    create_index()
    create_data_source()
    create_skillset()
    create_indexer()
    
    print("\n" + "=" * 50)
    print("✅ All components created!")
    print("=" * 50)
    print("\nNext steps:")
    print("1. Configure crawl depth (10) in Azure Portal:")
    print("   AI Search → Data Sources → policy-datasource")
    print("\n2. Run the indexer:")
    print("   python scripts/configure-search.py run-indexer")
    print("\n3. Check status:")
    print("   python scripts/configure-search.py status")


def main():
    """Main entry point."""
    import argparse
    
    parser = argparse.ArgumentParser(description="Azure AI Search Configuration")
    parser.add_argument("action", nargs="?", default="create-all",
                       choices=["create-all", "create-index", "create-datasource", 
                               "create-skillset", "create-indexer", "run-indexer", "status"],
                       help="Action to perform (default: create-all)")
    
    args = parser.parse_args()
    
    validate_config()
    
    actions = {
        "create-all": create_all,
        "create-index": create_index,
        "create-datasource": create_data_source,
        "create-skillset": create_skillset,
        "create-indexer": create_indexer,
        "run-indexer": run_indexer,
        "status": lambda: (get_indexer_status(), get_index_stats())
    }
    
    actions[args.action]()


if __name__ == "__main__":
    main()
