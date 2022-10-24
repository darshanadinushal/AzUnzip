using AzUnzipEverything.Models;
using System;
using System.Collections.Generic;
using System.Text;
using System.Threading.Tasks;

namespace AzUnzipEverything.Infrastructure.CosmosDb
{
    public interface ICosmosDbService
    {
        Task AddDocumentInfoAsync(DocumentInfo item);
    }
}
