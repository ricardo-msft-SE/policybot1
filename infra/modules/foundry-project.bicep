// ============================================================================
// Azure AI Foundry Project Module (hub-less)
// ============================================================================
// Creates a Foundry Project linked directly to an Azure AI Services account.
// This is the NEW Azure AI Foundry model — no Hub workspace is required.
// The project connects to AI Services via hubResourceId, which now accepts
// a CognitiveServices account resource ID (not a Hub ML workspace ID).
// ============================================================================

@description('Name of the Foundry project')
param name string

@description('Location for the resource')
param location string

@description('Resource ID of the Azure AI Services account to link this project to')
param aiServicesResourceId string

@description('Tags for the resource')
param tags object = {}

// ============================================================================
// Resources
// ============================================================================

resource foundryProject 'Microsoft.MachineLearningServices/workspaces@2025-01-01-preview' = {
  name: name
  location: location
  tags: tags
  kind: 'Project'
  sku: {
    name: 'Basic'
    tier: 'Basic'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    // In the new Foundry model this points to a CognitiveServices/AIServices account,
    // not a Hub ML workspace — this is the key difference from the classic approach.
    hubResourceId: aiServicesResourceId
    friendlyName: name
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('The name of the Foundry project')
output projectName string = foundryProject.name

@description('The resource ID of the Foundry project')
output projectId string = foundryProject.id

@description('The principal ID for the system-assigned managed identity')
output principalId string = foundryProject.identity.principalId
