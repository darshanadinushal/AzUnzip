using AzUnzipEverything;
using AzUnzipEverything.Extensions;
using AzUnzipEverything.Infrastructure.CosmosDb;
using Microsoft.Azure.Functions.Extensions.DependencyInjection;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using System;
using System.Configuration;
using System.Threading.Tasks;

[assembly: FunctionsStartup(typeof(Startup))]
namespace AzUnzipEverything
{
    public class Startup : FunctionsStartup
    {
        public override void Configure(IFunctionsHostBuilder builder)
        {
            var configurationBuilder = new ConfigurationBuilder()
                .SetBasePath(Environment.CurrentDirectory)
                .AddJsonFile("local.settings.json", optional: true, reloadOnChange: true)
                .AddEnvironmentVariables();

            builder.Services.AddAzureKeyVaultConfiguration(configurationBuilder);
            
            builder.Services.AddBlobStorage();

            builder.Services.AddSupportedArchiveTypes();

            builder.Services.AddSingleton<ICosmosDbService>(InitializeCosmosClientInstanceAsync(configurationBuilder).GetAwaiter().GetResult());
        }


        private  async Task<CosmosDbService> InitializeCosmosClientInstanceAsync(IConfigurationBuilder configurationBuilder)
        {
            var config = configurationBuilder.Build();
            IConfigurationSection configurationSection = config.GetSection("CosmosDb");

            string databaseName = configurationSection.GetSection("DatabaseName").Value;
            string containerName = configurationSection.GetSection("ContainerName").Value;
            string account = configurationSection.GetSection("Account").Value;
            string key = configurationSection.GetSection("Key").Value;
            Microsoft.Azure.Cosmos.CosmosClient client = new Microsoft.Azure.Cosmos.CosmosClient(account, key);
            CosmosDbService cosmosDbService = new CosmosDbService(client, databaseName, containerName);
            Microsoft.Azure.Cosmos.DatabaseResponse database = await client.CreateDatabaseIfNotExistsAsync(databaseName);
            await database.Database.CreateContainerIfNotExistsAsync(containerName, "/id");

            return cosmosDbService;
        }

    }
}
