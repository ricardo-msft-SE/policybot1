// ============================================================================
// Azure AI Services Module
// ============================================================================
// Deploys Azure AI Services (multi-service) for Microsoft Foundry integration
// This resource is required for Foundry IQ and agent capabilities
// ============================================================================

@description('Name of the Azure AI Services resource')
param name string

@description('Location for the resource')
param location string

@description('Tags for the resource')
param tags object = {}

// ============================================================================
// Resources
// ============================================================================

resource aiServices 'Microsoft.CognitiveServices/accounts@2024-04-01-preview' = {
  name: name
  location: location
  tags: tags
  kind: 'AIServices'
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

// ============================================================================
// Outputs
// ============================================================================

@description('The name of the deployed AI Services resource')
output serviceName string = aiServices.name

@description('The resource ID of the AI Services resource')
output resourceId string = aiServices.id

@description('The endpoint URL of the AI Services resource')
output endpoint string = aiServices.properties.endpoint

@description('The principal ID for managed identity (if system-assigned)')
output principalId string = aiServices.identity.?principalId ?? ''
