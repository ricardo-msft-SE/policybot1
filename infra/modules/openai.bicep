// ============================================================================
// Azure OpenAI Module
// ============================================================================
// Deploys Azure OpenAI Service with GPT-4o model for Policy Bot
// ============================================================================

@description('Name of the Azure OpenAI service')
param name string

@description('Location for the resource')
param location string

@description('Model deployment name')
param deploymentName string = 'gpt-4o'

@description('Model version')
param modelVersion string = '2024-08-06'

@description('Tokens per minute quota')
param tpm int = 30000

@description('Tags for the resource')
param tags object = {}

// ============================================================================
// Resources
// ============================================================================

resource openAiService 'Microsoft.CognitiveServices/accounts@2024-04-01-preview' = {
  name: name
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: name
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }
    // Disable local authentication for enhanced security (optional)
    disableLocalAuth: false
  }
}

// Deploy GPT-4o model
resource gpt4oDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-04-01-preview' = {
  parent: openAiService
  name: deploymentName
  sku: {
    name: 'Standard'
    capacity: tpm / 1000 // Capacity is in thousands
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o'
      version: modelVersion
    }
    raiPolicyName: 'Microsoft.Default'
  }
}

// Deploy text-embedding-ada-002 for vector search
resource embeddingDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-04-01-preview' = {
  parent: openAiService
  name: 'text-embedding-ada-002'
  sku: {
    name: 'Standard'
    capacity: 120 // 120K TPM for embeddings
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'text-embedding-ada-002'
      version: '2'
    }
    raiPolicyName: 'Microsoft.Default'
  }
  dependsOn: [gpt4oDeployment] // Sequential deployment to avoid conflicts
}

// ============================================================================
// Outputs
// ============================================================================

@description('The name of the deployed OpenAI service')
output serviceName string = openAiService.name

@description('The resource ID of the OpenAI service')
output resourceId string = openAiService.id

@description('The endpoint URL of the OpenAI service')
output endpoint string = openAiService.properties.endpoint

@description('The GPT-4o deployment name')
output gpt4oDeploymentName string = gpt4oDeployment.name

@description('The embedding deployment name')
output embeddingDeploymentName string = embeddingDeployment.name
