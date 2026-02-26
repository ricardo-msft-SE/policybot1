// ============================================================================
// Azure AI Search Module
// ============================================================================
// Deploys Azure AI Search with optional semantic search capabilities
// Configured for web crawling and vector search for Policy Bot
// ============================================================================

@description('Name of the Azure AI Search service')
param name string

@description('Location for the resource')
param location string

@description('SKU for the search service')
@allowed(['basic', 'standard', 'standard2', 'standard3'])
param sku string = 'basic'

@description('Number of replicas (3+ for 99.9% SLA)')
@minValue(1)
@maxValue(12)
param replicaCount int = 1

@description('Number of partitions')
@allowed([1, 2, 3, 4, 6, 12])
param partitionCount int = 1

@description('Enable semantic search capability')
param enableSemanticSearch bool = true

@description('Tags for the resource')
param tags object = {}

// ============================================================================
// Resources
// ============================================================================

resource searchService 'Microsoft.Search/searchServices@2023-11-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: sku
  }
  properties: {
    replicaCount: replicaCount
    partitionCount: partitionCount
    hostingMode: 'default'
    publicNetworkAccess: 'enabled'
    // Semantic search configuration
    semanticSearch: enableSemanticSearch ? 'free' : 'disabled'
    // Authentication options
    authOptions: {
      apiKeyOnly: {}
    }
    // Disable local authentication for production (optional)
    disableLocalAuth: false
    // Encryption configuration (uses Microsoft-managed keys by default)
    encryptionWithCmk: {
      enforcement: 'Unspecified'
    }
  }
}

// ============================================================================
// Diagnostic Settings (optional - uncomment if Log Analytics workspace is available)
// ============================================================================

// resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
//   name: 'search-diagnostics'
//   scope: searchService
//   properties: {
//     workspaceId: logAnalyticsWorkspaceId
//     logs: [
//       {
//         category: 'OperationLogs'
//         enabled: true
//       }
//     ]
//     metrics: [
//       {
//         category: 'AllMetrics'
//         enabled: true
//       }
//     ]
//   }
// }

// ============================================================================
// Outputs
// ============================================================================

@description('The name of the deployed search service')
output serviceName string = searchService.name

@description('The resource ID of the search service')
output resourceId string = searchService.id

@description('The endpoint URL of the search service')
output endpoint string = 'https://${searchService.name}.search.windows.net'

@description('The admin key (use Azure Key Vault in production)')
output adminKeySecretRef string = 'Use: az search admin-key show --service-name ${searchService.name} --resource-group <rg-name>'
