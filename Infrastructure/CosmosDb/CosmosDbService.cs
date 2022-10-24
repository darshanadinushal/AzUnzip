using System.Threading.Tasks;
using AzUnzipEverything.Models;
using Microsoft.Azure.Cosmos;

namespace AzUnzipEverything.Infrastructure.CosmosDb
{
    public class CosmosDbService : ICosmosDbService
    {
        private Container _container;

        public CosmosDbService(
            CosmosClient dbClient,
            string databaseName,
            string containerName)
        {
            this._container = dbClient.GetContainer(databaseName, containerName);
        }

        public async Task AddDocumentInfoAsync(DocumentInfo item)
        {
            await this._container.CreateItemAsync<DocumentInfo>(item, new PartitionKey(item.documentId));
        }
        
    }
}
