@description('Name use as base-template to named the resources deployed in Azure.')
param baseName string = 'UnzipEverything'

@description('Name of the branch to use when deploying (Default = master).')
param GitHubBranch string = 'master'

@description('Name of the storage account where the files will be drop and unziped. (Default = dropzone).')
param MonitorStorageName string = 'dropzone'

@description('Specifies whether the key vault is a standard vault or a premium vault.')
@allowed([
  'Standard'
  'Premium'
])
param KeyVaultSkuName string = 'Standard'

param location string = resourceGroup().location

@description('Password for unzipping secure/encrypted zip files')
@secure()
param PasswordForZips string

var suffix = substring(toLower(uniqueString(resourceGroup().id, location)), 0, 5)
var funcAppName = toLower('${baseName}${suffix}')
var KeyVaultName = toLower('${baseName}-kv-${suffix}')
var funcStorageName = toLower('${substring(baseName, 0, min(length(baseName), 16))}stg${suffix}')
var serverFarmName = '${substring(baseName, 0, min(length(baseName), 14))}-srv-${suffix}'
var repoURL = 'https://github.com/darshanadinushal/AzUnzip.git'
var fileStorageName = toLower('${substring(MonitorStorageName, 0, min(length(MonitorStorageName), 16))}stg${suffix}')

resource funcApp 'Microsoft.Web/sites@2018-11-01' = {
  name: funcAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: serverFarm.id
    siteConfig: {
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
          value: '~3'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'dotnet'
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
          value: 'https://${KeyVaultName}.vault.azure.net/'
        }
      ]
    }
  }
  dependsOn: [

    funcStorage
  ]
}

resource funcAppName_web 'Microsoft.Web/sites/sourcecontrols@2018-11-01' = {
  parent: funcApp
  name: 'web'
  properties: {
    repoUrl: repoURL
    branch: GitHubBranch
    publishRunbook: true
    isManualIntegration: true
  }
}

resource funcStorage 'Microsoft.Storage/storageAccounts@2018-07-01' = {
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

resource serverFarm 'Microsoft.Web/serverfarms@2018-02-01' = {
  name: serverFarmName
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {
    name: serverFarmName
    computeMode: 'Dynamic'
  }
}

resource fileStorage 'Microsoft.Storage/storageAccounts@2018-07-01' = {
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

resource fileStorageName_default_input_files 'Microsoft.Storage/storageAccounts/blobServices/containers@2018-07-01' = {
  name: '${fileStorageName}/default/input-files'
  properties: {
    publicAccess: 'Blob'
  }
  dependsOn: [
    fileStorage
  ]
}

resource fileStorageName_default_output_files 'Microsoft.Storage/storageAccounts/blobServices/containers@2018-07-01' = {
  name: '${fileStorageName}/default/output-files'
  properties: {
    publicAccess: 'Blob'
  }
  dependsOn: [
    fileStorage
  ]
}

resource KeyVault 'Microsoft.KeyVault/vaults@2016-10-01' = {
  name: KeyVaultName
  location: location
  properties: {
    enabledForDeployment: true
    enabledForDiskEncryption: true
    enabledForTemplateDeployment: true
    tenantId: subscription().tenantId
    accessPolicies: []
    resources: []
    sku: {
      name: KeyVaultSkuName
      family: 'A'
    }
  }
  dependsOn: []
}

resource KeyVaultName_add 'Microsoft.KeyVault/vaults/accessPolicies@2018-02-14' = {
  parent: KeyVault
  name: 'add'
  properties: {
    accessPolicies: [
      {
        tenantId: reference(funcApp.id, '2018-11-01', 'Full').identity.tenantId
        objectId: reference(funcApp.id, '2018-11-01', 'Full').identity.principalId
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

resource KeyVaultName_ZipPassword 'Microsoft.KeyVault/vaults/secrets@2016-10-01' = {
  parent: KeyVault
  name: 'ZipPassword'
  location: location
  properties: {
    value: PasswordForZips
  }
}
