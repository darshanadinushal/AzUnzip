using AzUnzipEverything.Infrastructure.CosmosDb;
using AzUnzipEverything.Models;
using Microsoft.Extensions.Logging;
using Microsoft.WindowsAzure.Storage;
using Microsoft.WindowsAzure.Storage.Blob;
using SharpCompress.Archives;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading.Tasks;

namespace AzUnzipEverything.Abstractions
{
    public abstract class FileProcessorBase : IFileProcessor
    {
        private readonly CloudBlobContainer _destinationContainer;
        private readonly ICosmosDbService _cosmosDbService;
        private readonly ILogger<FileProcessorBase> _logger;

        protected FileProcessorBase(CloudBlobContainer destinationContainer, ILogger<FileProcessorBase> logger , ICosmosDbService cosmosDbService)
        {
            _destinationContainer = destinationContainer;
            _logger = logger;
            _cosmosDbService = cosmosDbService;
        }

        public abstract Task ProcessFile(Stream blobStream);

        protected async Task ExtractArchiveFiles(IEnumerable<IArchiveEntry> archiveEntries)
        {
            try
            {
                _logger.LogInformation($"Start ExtractArchiveFiles remove");
                foreach (var archiveEntry in archiveEntries.Where(entry => !entry.IsDirectory))
                {
                    _logger.LogInformation($"Now processing {archiveEntry.Key}");

                    var documentinfo = new DocumentInfo
                    {
                        Id = Guid.NewGuid().ToString(),
                        documentId = archiveEntry.Key,
                        Completed = true,
                        Size = archiveEntry.Size,
                        Name = $"file{DateTime.Now.ToLongTimeString()}",
                        Description = "Upload"
                    };

                    NameValidator.ValidateBlobName(archiveEntry.Key);

                    var blockBlob = _destinationContainer.GetBlockBlobReference(archiveEntry.Key);
                    await using var fileStream = archiveEntry.OpenEntryStream();
                    await blockBlob.UploadFromStreamAsync(fileStream);
                    await _cosmosDbService.AddDocumentInfoAsync(documentinfo);
                    _logger.LogInformation(
                        $"{archiveEntry.Key} processed successfully and moved to destination container");
                }
            }
            catch (Exception ex)
            {
                _logger.LogError("Error log ExtractArchiveFiles");
                _logger.LogError(ex.StackTrace);
                _logger.LogError(ex.Message);
            }
            
        }
    }
}