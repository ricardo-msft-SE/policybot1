// ============================================================================
// Log Analytics Workspace Module
// ============================================================================
// Deploys Log Analytics Workspace for centralized logging and monitoring
// ============================================================================

@description('Name of the Log Analytics workspace')
param name string

@description('Location for the resource')
param location string

@description('Retention period in days')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('Tags for the resource')
param tags object = {}

// ============================================================================
// Resources
// ============================================================================

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    workspaceCapping: {
      dailyQuotaGb: 1 // Limit to control costs
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('The name of the deployed Log Analytics workspace')
output name string = logAnalyticsWorkspace.name

@description('The resource ID of the Log Analytics workspace')
output workspaceId string = logAnalyticsWorkspace.id

@description('The customer ID (workspace ID) for Log Analytics')
output customerId string = logAnalyticsWorkspace.properties.customerId
