// ============================================================================
// Policy Bot - Main Infrastructure Deployment
// ============================================================================
// This Bicep template deploys all Azure resources required for Policy Bot
// 
// Resources deployed:
// - Azure AI Search (for document indexing and retrieval)
// - Azure OpenAI Service (for LLM capabilities)
// - Azure AI Services (multi-service resource for Foundry)
// - Application Insights (for monitoring)
// - Log Analytics Workspace (for diagnostics)
// ============================================================================

targetScope = 'resourceGroup'

// ============================================================================
// Parameters
// ============================================================================

@description('Location for all resources')
param location string = resourceGroup().location

@description('Unique suffix for resource names (leave empty for auto-generated)')
param uniqueSuffix string = uniqueString(resourceGroup().id)

@description('Azure AI Search SKU')
@allowed(['basic', 'standard', 'standard2', 'standard3'])
param searchSku string = 'basic'

@description('Azure AI Search replica count (3+ for 99.9% SLA)')
@minValue(1)
@maxValue(12)
param searchReplicaCount int = 1

@description('Azure AI Search partition count')
@allowed([1, 2, 3, 4, 6, 12])
param searchPartitionCount int = 1

@description('Enable semantic search')
param enableSemanticSearch bool = true

@description('Azure OpenAI model deployment name')
param openAiDeploymentName string = 'gpt-4o'

@description('Azure OpenAI model version')
param openAiModelVersion string = '2024-08-06'

@description('Azure OpenAI TPM (tokens per minute) quota')
param openAiTpm int = 30000

@description('Name of the Foundry Project (hub-less)')
param foundryProjectName string = 'policybot-project'

@description('Tags for all resources')
param tags object = {
  project: 'policybot'
  environment: 'production'
  managedBy: 'bicep'
}

// ============================================================================
// Variables
// ============================================================================

var baseName = 'policybot'
var searchServiceName = 'search-${baseName}-${uniqueSuffix}'
var openAiServiceName = 'aoai-${baseName}-${uniqueSuffix}'
var aiServicesName = 'ais-${baseName}-${uniqueSuffix}'
var logAnalyticsName = 'log-${baseName}-${uniqueSuffix}'
var appInsightsName = 'appi-${baseName}-${uniqueSuffix}'
// Foundry Project name is passed in so users can override from bootstrap.ps1

// ============================================================================
// Modules
// ============================================================================

// Log Analytics Workspace (required for Application Insights)
module logAnalytics 'modules/log-analytics.bicep' = {
  name: 'deploy-log-analytics'
  params: {
    name: logAnalyticsName
    location: location
    tags: tags
  }
}

// Application Insights
module appInsights 'modules/app-insights.bicep' = {
  name: 'deploy-app-insights'
  params: {
    name: appInsightsName
    location: location
    logAnalyticsWorkspaceId: logAnalytics.outputs.workspaceId
    tags: tags
  }
}

// Azure AI Search
module search 'modules/ai-search.bicep' = {
  name: 'deploy-ai-search'
  params: {
    name: searchServiceName
    location: location
    sku: searchSku
    replicaCount: searchReplicaCount
    partitionCount: searchPartitionCount
    enableSemanticSearch: enableSemanticSearch
    tags: tags
  }
}

// Azure OpenAI Service
module openAi 'modules/openai.bicep' = {
  name: 'deploy-openai'
  params: {
    name: openAiServiceName
    location: location
    deploymentName: openAiDeploymentName
    modelVersion: openAiModelVersion
    tpm: openAiTpm
    tags: tags
  }
}

// Azure AI Services (for Foundry)
module aiServices 'modules/ai-services.bicep' = {
  name: 'deploy-ai-services'
  params: {
    name: aiServicesName
    location: location
    tags: tags
  }
}

// Azure AI Foundry Project (hub-less — links directly to AI Services)
// New model: no Hub workspace required; hubResourceId points to a
// CognitiveServices/AIServices account instead of an ML Hub workspace.
module foundryProject 'modules/foundry-project.bicep' = {
  name: 'deploy-foundry-project'
  params: {
    name: foundryProjectName
    location: location
    aiServicesResourceId: aiServices.outputs.resourceId
    tags: tags
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Azure AI Search service name')
output searchServiceName string = search.outputs.serviceName

@description('Azure AI Search endpoint')
output searchEndpoint string = search.outputs.endpoint

@description('Azure OpenAI service name')
output openAiServiceName string = openAi.outputs.serviceName

@description('Azure OpenAI endpoint')
output openAiEndpoint string = openAi.outputs.endpoint

@description('Azure AI Services name')
output aiServicesName string = aiServices.outputs.serviceName

@description('Azure AI Services endpoint')
output aiServicesEndpoint string = aiServices.outputs.endpoint

@description('Application Insights name')
output appInsightsName string = appInsights.outputs.name

@description('Application Insights connection string')
output appInsightsConnectionString string = appInsights.outputs.connectionString

@description('Log Analytics workspace ID')
output logAnalyticsWorkspaceId string = logAnalytics.outputs.workspaceId

@description('Resource group name')
output resourceGroupName string = resourceGroup().name

@description('Deployment location')
output location string = location

@description('Foundry Project name')
output foundryProjectName string = foundryProject.outputs.projectName

@description('Foundry Project resource ID')
output foundryProjectId string = foundryProject.outputs.projectId
