@description('The name of the EventHub namespace')
param eventHubNamespaceName string

@description('The name of the Event Hub')
param eventHubName string

@description('Name of the SQL Server')
param sqlServerName string

@description('The administrator username of the SQL Server')
param sqlServerUserName string

@description('The administrator password of the SQL Server')
@secure()
param sqlServerPassword string

@description('The name of the SQL Server database')
param sqlServerDatabaseName string

@description('The name of the storage account')
param storageName string

@description('The name of the function app')
param functionAppName string

var blobContainerName = 'windturbinecapture'
var functionAppPlanName = '${functionAppName}Plan'
var storageAccountid = '${resourceGroup().id}/providers/Microsoft.Storage/storageAccounts/${storageName}'
var guid_role_assign_containers_write = guid('rsgRoleAssignmentNameContainersWrite')
var guid_role_assign_containers_blobs_write = guid('rsgRoleAssignmentNameContainersBlobsWrite')
var resource_group_location = resourceGroup().location

resource eventHubNamespace 'Microsoft.EventHub/namespaces@2017-04-01' = {
  name: eventHubNamespaceName
  location: resource_group_location
  sku: {
    name: 'Standard'
  }
  properties: {
    isAutoInflateEnabled: true
    maximumThroughputUnits: 7
  }
  dependsOn: [
    role_assignment_containers_blobs_write
  ]
}

resource eventHubNamespaceName_eventHub 'Microsoft.EventHub/namespaces/EventHubs@2017-04-01' = {
  parent: eventHubNamespace
  name: eventHubName
  properties: {
    messageRetentionInDays: 1
    partitionCount: 2
    captureDescription: {
      enabled: true
      encoding: 'Avro'
      intervalInSeconds: 60
      sizeLimitInBytes: 314572800
      destination: {
        name: 'EventHubArchive.AzureBlockBlob'
        properties: {
          storageAccountResourceId: storage.id
          blobContainer: blobContainerName
          archiveNameFormat: '{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}'
        }
      }
    }
  }
}

resource sqlServer 'Microsoft.Sql/servers@2014-04-01' = {
  name: sqlServerName
  location: resource_group_location
  properties: {
    administratorLogin: sqlServerUserName
    administratorLoginPassword: sqlServerPassword
    version: '12.0'
  }
}

resource sqlServerName_sqlServerDatabase 'Microsoft.Sql/servers/databases@2017-10-01-preview' = {
  parent: sqlServer
  name: sqlServerDatabaseName
  location: resource_group_location
  sku: {
    name: 'DW100c'
    tier: 'DataWarehouse'
  }
  properties: {
    collation: 'SQL_Latin1_General_CP1_CI_AS'
  }
}

resource sqlServerName_AllowAllAzureIps 'Microsoft.Sql/servers/firewallRules@2014-04-01' = {
  parent: sqlServer
  name: 'AllowAllAzureIps'
  properties: {
    endIpAddress: '0.0.0.0'
    startIpAddress: '0.0.0.0'
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2016-01-01' = {
  name: storageName
  location: resource_group_location
  sku: {
    name: 'Standard_LRS'
    // tier: 'Standard'
  }
  kind: 'Storage'
  tags: {}
  // scale: null
  properties: {}
  dependsOn: []
}

resource role_assignment_containers_write 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid_role_assign_containers_write
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'Microsoft.Storage/storageAccounts/blobServices/containers/write')
    principalId: 'c1d5bfd7-b4fa-48c7-ae62-6984d0bfb4e3'
    // scope: storageAccountid
  }
  dependsOn: [
    storage
  ]
}

resource role_assignment_containers_blobs_write 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid_role_assign_containers_blobs_write
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write')
    principalId: 'c1d5bfd7-b4fa-48c7-ae62-6984d0bfb4e3'
    // scope: storageAccountid
  }
  dependsOn: [
    role_assignment_containers_write
  ]
}

resource functionAppPlan 'Microsoft.Web/serverfarms@2015-08-01' = {
  name: functionAppPlanName
  location: resource_group_location
  kind: 'functionapp'
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
    size: 'Y1'
    family: 'Y'
    capacity: 0
  }
  properties: {
    name: functionAppPlanName 
    // status:
    // numberOfWorkers: 0
  }
}

resource functionApp 'Microsoft.Web/sites@2016-08-01' = {
  name: functionAppName
  location: resource_group_location
  kind: 'functionapp'
  properties: {
    serverFarmId: functionAppPlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsDashboard'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageName};AccountKey=${listKeys(storageAccountid, '2015-05-01-preview').key1}'
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageName};AccountKey=${listKeys(storageAccountid, '2015-05-01-preview').key1}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageName};AccountKey=${listKeys(storageAccountid, '2015-05-01-preview').key1}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'StorageConnectionString'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageName};AccountKey=${listKeys(storageAccountid, '2015-05-01-preview').key1}'
        }
        {
          name: 'SqlDwConnection'
          value: 'Server=tcp:${sqlServerName}.database.windows.net,1433;Database=${sqlServerDatabaseName};Trusted_Connection=False;User ID=${sqlServerUserName}@${sqlServerName};Password=${sqlServerPassword};Connection Timeout=30;Encrypt=True'
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~1'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '6.5.0'
        }
      ]
    }
  }
  dependsOn: [

    role_assignment_containers_blobs_write
  ]
}
