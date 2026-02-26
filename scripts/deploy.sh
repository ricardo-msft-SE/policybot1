#!/bin/bash
# ============================================================================
# Policy Bot - Deployment Script (Bash)
# ============================================================================
# This script deploys all Azure resources required for Policy Bot
# Run from the repository root directory
# ============================================================================

set -e

# ============================================================================
# Configuration
# ============================================================================

RESOURCE_GROUP="${RESOURCE_GROUP:-rg-policybot}"
LOCATION="${LOCATION:-eastus2}"
SEARCH_SKU="${SEARCH_SKU:-basic}"
SEARCH_REPLICA_COUNT="${SEARCH_REPLICA_COUNT:-1}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Functions
step() { echo -e "\n${CYAN}>> $1${NC}"; }
success() { echo -e "   ${GREEN}[OK]${NC} $1"; }
warning() { echo -e "   ${YELLOW}[!]${NC} $1"; }
error() { echo -e "   ${RED}[X]${NC} $1"; exit 1; }

# ============================================================================
# Prerequisites Check
# ============================================================================

step "Checking prerequisites..."

# Check Azure CLI
if ! command -v az &> /dev/null; then
    error "Azure CLI not found. Install from: https://docs.microsoft.com/cli/azure/install-azure-cli"
fi

AZ_VERSION=$(az version --query '"azure-cli"' -o tsv)
success "Azure CLI version: $AZ_VERSION"

# Check login status
if ! az account show &> /dev/null; then
    warning "Not logged in to Azure. Running 'az login'..."
    az login
fi

ACCOUNT_NAME=$(az account show --query "name" -o tsv)
USER_NAME=$(az account show --query "user.name" -o tsv)
success "Logged in as: $USER_NAME"
success "Subscription: $ACCOUNT_NAME"

# ============================================================================
# Register Resource Providers
# ============================================================================

step "Registering required resource providers..."

PROVIDERS=(
    "Microsoft.Search"
    "Microsoft.CognitiveServices"
    "Microsoft.Insights"
    "Microsoft.OperationalInsights"
)

for PROVIDER in "${PROVIDERS[@]}"; do
    STATUS=$(az provider show --namespace "$PROVIDER" --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")
    if [ "$STATUS" != "Registered" ]; then
        echo -n "   Registering $PROVIDER..."
        az provider register --namespace "$PROVIDER" --wait > /dev/null
        success "$PROVIDER registered"
    else
        success "$PROVIDER already registered"
    fi
done

# ============================================================================
# Create Resource Group
# ============================================================================

step "Creating resource group: $RESOURCE_GROUP"

RG_EXISTS=$(az group exists --name "$RESOURCE_GROUP")
if [ "$RG_EXISTS" == "true" ]; then
    warning "Resource group '$RESOURCE_GROUP' already exists"
else
    az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
    success "Resource group created"
fi

# ============================================================================
# Deploy Infrastructure
# ============================================================================

step "Deploying infrastructure with Bicep..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="$SCRIPT_DIR/../infra/main.bicep"

if [ ! -f "$TEMPLATE_FILE" ]; then
    error "Bicep template not found at: $TEMPLATE_FILE"
fi

echo "   Deploying resources (this may take 5-10 minutes)..."

az deployment group create \
    --resource-group "$RESOURCE_GROUP" \
    --template-file "$TEMPLATE_FILE" \
    --parameters \
        location="$LOCATION" \
        searchSku="$SEARCH_SKU" \
        searchReplicaCount="$SEARCH_REPLICA_COUNT" \
    --output none

if [ $? -eq 0 ]; then
    success "Deployment completed successfully!"
else
    error "Deployment failed"
fi

# ============================================================================
# Display Outputs
# ============================================================================

step "Deployment Outputs:"

echo ""
az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name "main" \
    --query "properties.outputs" \
    --output table

# Get specific outputs for next steps
SEARCH_NAME=$(az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name "main" \
    --query "properties.outputs.searchServiceName.value" \
    -o tsv)

OPENAI_NAME=$(az deployment group show \
    --resource-group "$RESOURCE_GROUP" \
    --name "main" \
    --query "properties.outputs.openAiServiceName.value" \
    -o tsv)

# ============================================================================
# Next Steps
# ============================================================================

step "Next Steps:"

cat << EOF

   1. Configure Azure AI Search crawler:
      - Navigate to Azure Portal > AI Search > $SEARCH_NAME
      - Create a data source pointing to: https://codes.ohio.gov/ohio-revised-code
      - Set crawl depth to 10+
      
   2. Create the Foundry Agent:
      - Navigate to https://ai.azure.com
      - Create a new project
      - Create a Prompt Agent with the system prompt from: foundry/prompts/system-prompt.md
      - Connect to your AI Search index

   3. Test the agent:
      - Use the Foundry chat interface
      - Verify citations are included in responses

   Documentation: docs/deployment-guide.md

EOF

success "Deployment script completed!"
