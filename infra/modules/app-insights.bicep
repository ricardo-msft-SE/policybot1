// ============================================================================
// Application Insights Module
// ============================================================================
// Deploys Application Insights for monitoring Policy Bot usage and performance
// ============================================================================

@description('Name of the Application Insights resource')
param name string

@description('Location for the resource')
param location string

@description('Log Analytics Workspace ID for data storage')
param logAnalyticsWorkspaceId string

@description('Tags for the resource')
param tags object = {}

// ============================================================================
// Resources
// ============================================================================

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: name
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspaceId
    IngestionMode: 'LogAnalytics'
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    // Sampling to control costs
    SamplingPercentage: 100
    // Retention
    RetentionInDays: 90
    // Disable IP masking for debugging (enable in production)
    DisableIpMasking: false
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('The name of the deployed Application Insights resource')
output name string = appInsights.name

@description('The resource ID of the Application Insights resource')
output resourceId string = appInsights.id

@description('The instrumentation key for Application Insights')
output instrumentationKey string = appInsights.properties.InstrumentationKey

@description('The connection string for Application Insights')
output connectionString string = appInsights.properties.ConnectionString
