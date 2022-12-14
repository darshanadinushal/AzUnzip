@description('Name use as base-template to named the resources deployed in Azure.')
param baseName string = 'UnzipEverything'

@description('Name of the branch to use when deploying (Default = master).')
param GitHubBranch string = 'master'

@description('Name of the storage account where the files will be drop and unziped. (Default = dropzone).')
param MonitorStorageName string = 'dropzone'

param location string = resourceGroup().location

@description('Password for unzipping secure/encrypted zip files')
@secure()
param PasswordForZips string

@description('Enable public network traffic to access the account; if set to Disabled, public network traffic will be blocked even before the private endpoint is created')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Disabled'

@description('The name for the database')
param databaseName string

@description('The name for the SQL API container')
param containerName string

var suffix = substring(toLower(uniqueString(resourceGroup().id, location)), 0, 5)
var funcAppName = toLower('${baseName}${suffix}')
var KeyVaultName = toLower('${baseName}-kv-${suffix}')
var funcStorageName = toLower('${substring(baseName, 0, min(length(baseName), 16))}stg${suffix}')
var serverFarmName = '${substring(baseName, 0, min(length(baseName), 14))}-srv-${suffix}'
var repoURL = 'https://github.com/darshanadinushal/AzUnzip.git'
var fileStorageName = toLower('${substring(MonitorStorageName, 0, min(length(MonitorStorageName), 16))}stg${suffix}')
var virtualNetworkName = toLower('${baseName}-vpn-${suffix}')
var subnet1Name = toLower('${baseName}-sub1-${suffix}')
var subnet2Name = toLower('${baseName}-sub2-${suffix}')
var nsgName = toLower('${baseName}-nsg-${suffix}')
var sharedRules = loadJsonContent('./shared-nsg-rules.json', 'securityRules')
var databaseAccountName = toLower('${baseName}-consmosdb-${suffix}')
var dbEndpointName = toLower('${baseName}-consmosdb-${suffix}')
var privatelinkEndpoint ='privatelink.documents.azure.com'
var vnetLinkName =toLower('${baseName}-vlink-${suffix}')

var customRules = []
resource nsg 'Microsoft.Network/networkSecurityGroups@2022-05-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: concat(sharedRules, customRules)
  }
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2022-05-01' = {
  name: virtualNetworkName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        '10.0.0.0/16'
      ]
    }
    subnets: [
      {
        name: subnet1Name
        properties: {
          addressPrefix: '10.0.0.0/24'
          networkSecurityGroup: nsg.id == '' ? null : {
            id: nsg.id
          } 
        }
      }
      {
        name: subnet2Name
        properties: {
          addressPrefix: '10.0.1.0/24'
          delegations: [
            {
                name: 'Microsoft.Web.serverFarms'
                properties: {
                    serviceName: 'Microsoft.Web/serverFarms'
                }
            } 
        ]
        }
        
      }
    ]
  }

  resource subnet1 'subnets' existing = {
    name: subnet1Name
  }

  resource subnet2 'subnets' existing = {
    name: subnet2Name
  }
}

var locations = [
  {
    locationName: location
    failoverPriority: 0
    isZoneRedundant: false
  }
]

resource databaseAccount 'Microsoft.DocumentDB/databaseAccounts@2022-08-15' = {
  name: databaseAccountName
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: locations
    enableFreeTier: true
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: false
    enableMultipleWriteLocations: false
    publicNetworkAccess: publicNetworkAccess
  }
}



resource privateEndpoint 'Microsoft.Network/privateEndpoints@2022-05-01' = {
  name: dbEndpointName
  location: location
  properties: {
    subnet: {
    id: virtualNetwork::subnet1.id
    }
    privateLinkServiceConnections: [
      {
        name: 'privateLinkcosmosdbcon'
        properties: {
          privateLinkServiceId: databaseAccount.id
          groupIds: [
            'Sql'
          ]
        }
      }
    ]
  }
}

resource privateDnsZones 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: privatelinkEndpoint
  location: 'global'
  properties: {}
}

resource privatelinkvnet 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  name: vnetLinkName
  location: 'global'
  parent: privateDnsZones
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: virtualNetwork.id
    }
  }
}

resource privateDnsZone 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2022-05-01' = {
  name: toLower('${vnetLinkName}-privateDnsZone-${suffix}')
  parent: privateEndpoint
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privateDnsZoneConfigs'
        properties: {
          privateDnsZoneId: privateDnsZones.id
        }
      }
    ]
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2022-08-15' = {
  parent: databaseAccount
  name: databaseName
  properties: {
    resource: {
      id: databaseName
    }
  }
}

resource container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2022-08-15' = {
  parent: database
  name: containerName
  properties: {
    resource: {
      id: containerName
      partitionKey: {
        paths: [
          '/documentId'
        ]
        kind: 'Hash'
      }
      indexingPolicy: {
        indexingMode: 'consistent'
        includedPaths: [
          {
            path: '/*'
          }
        ]
        excludedPaths: [
          {
            path: '/_etag/?'
          }
        ]
      }
    }
  }
}

resource sourcecontrolweb 'Microsoft.Web/sites/sourcecontrols@2022-03-01' = {
  parent: funcApp
  name: 'web'
  properties: {
    repoUrl: repoURL
    branch: GitHubBranch
    isManualIntegration: true
  }
}

resource funcStorage 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: funcStorageName
  location: location
  tags: {
    displayName: 'funStorageName'
  }
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
}

resource serverFarm 'Microsoft.Web/serverfarms@2022-03-01' = {
  name: serverFarmName
  location: location
  sku: {
    name: 'EP1'
    tier: 'ElasticPremium'
    family: 'EP'
  }
  kind: 'elastic'
  properties: {
    maximumElasticWorkerCount: 20
  }
}

resource fileStorage 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: fileStorageName
  location: location
  tags: {
    displayName: fileStorageName
  }
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
}

resource fileStorageName_default_input_files 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-05-01' = {
  name: '${fileStorageName}/default/input-files'
  properties: {
    publicAccess: 'Blob'
  }
  dependsOn: [
    fileStorage
  ]
}

resource fileStorageName_default_output_files 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-05-01' = {
  name: '${fileStorageName}/default/output-files'
  properties: {
    publicAccess: 'Blob'
  }
  dependsOn: [
    fileStorage
  ]
}

resource KeyVault 'Microsoft.KeyVault/vaults@2022-07-01' = {
  name: KeyVaultName
  location: location
  properties: {
    enabledForDeployment: true
    enabledForDiskEncryption: true
    enabledForTemplateDeployment: true
    tenantId: subscription().tenantId
    accessPolicies: []
    sku: {
      name: 'standard'
      family: 'A'
    }
  }
  dependsOn: []
}

var endpoint = KeyVault.properties.vaultUri

resource KeyVaultName_add 'Microsoft.KeyVault/vaults/accessPolicies@2022-07-01' = {
  parent: KeyVault
  name: 'add'
  properties: {
    accessPolicies: [
      {
        tenantId: reference(funcApp.id, '2022-03-01', 'Full').identity.tenantId
        objectId: reference(funcApp.id, '2022-03-01', 'Full').identity.principalId
        permissions: {
          secrets: [
            'list'
            'get'
          ]
        }
      }
    ]
  }
}

resource KeyVaultName_ZipPassword 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: KeyVault
  name: 'ZipPassword'
  properties: {
    value: PasswordForZips
  }
}

resource KeyVaultName_CosmosDb 'Microsoft.KeyVault/vaults/secrets@2022-07-01' = {
  parent: KeyVault
  name: 'CosmosDb'
  properties: {
    value: databaseAccount.listConnectionStrings().connectionStrings[0].connectionString
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: funcAppName
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
  }
}

resource funcApp 'Microsoft.Web/sites@2022-03-01' = {
  name: funcAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: serverFarm.id
    virtualNetworkSubnetId: virtualNetwork::subnet2.id
    siteConfig: {
      vnetRouteAllEnabled: true
      appSettings: [
        {
          name: 'AzureWebJobsDashboard'
          value: 'DefaultEndpointsProtocol=https;AccountName=${funcStorageName};AccountKey=${listKeys(funcStorageName, '2015-05-01-preview').key1}'
        }
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${funcStorageName};AccountKey=${listKeys(funcStorageName, '2015-05-01-preview').key1}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${funcStorageName};AccountKey=${listKeys(funcStorageName, '2015-05-01-preview').key1}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: funcAppName
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'cloud5mins_storage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${fileStorageName};AccountKey=${listKeys(fileStorageName, '2015-05-01-preview').key1}'
        }
        {
          name: 'destinationStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${fileStorageName};AccountKey=${listKeys(fileStorageName, '2015-05-01-preview').key1}'
        }
        {
          name: 'destinationContainer'
          value: 'output-files'
        }
        {
          name: 'KeyVaultUri'
          value: endpoint
        }
      ]
    }
  }
  dependsOn: [
    funcStorage
  ]
}

resource functionToSubnet 'Microsoft.Web/sites/networkConfig@2020-06-01' = {
  name: '${funcAppName}/virtualNetwork'
  properties: {
    subnetResourceId: virtualNetwork::subnet2.id
    swiftSupported: true
  }
  dependsOn:[
    funcApp
  ]
}


