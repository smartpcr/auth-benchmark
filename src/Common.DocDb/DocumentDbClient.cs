// --------------------------------------------------------------------------------------------------------------------
// <copyright file="DocumentDbClient.cs" company="Microsoft">
// </copyright>
// <summary>
//  The ElectricalDatacenterHealthService
// </summary>
// --------------------------------------------------------------------------------------------------------------------

using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Common.KeyVault;
using EnsureThat;
using Microsoft.Azure.Documents;
using Microsoft.Azure.Documents.Client;
using Microsoft.Azure.Documents.Linq;
using Microsoft.Azure.KeyVault;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Newtonsoft.Json;
using Newtonsoft.Json.Serialization;

namespace Common.DocDb
{
    public sealed class DocumentDbClient : IDocumentDbClient
    {
        private readonly DocDbSettings _settings;
        private readonly ILogger<DocumentDbClient> _logger;
        private readonly FeedOptions _feedOptions;


        public DocumentCollection Collection { get; private set; }
        public DocumentClient Client { get; }

        public DocumentDbClient(
            IKeyVaultClient kvClient,
            IOptions<VaultSettings> vaultSettings,
            DocDbSettings dbSettings,
            ILogger<DocumentDbClient> logger)
        {
            _settings = dbSettings;
            _logger = logger;

            _logger.LogInformation($"Retrieving auth key '{_settings.AuthKeySecret}' from vault '{vaultSettings.Value.VaultName}'");
            var authKey = kvClient.GetSecretAsync(
                vaultSettings.Value.VaultUrl,
                _settings.AuthKeySecret).GetAwaiter().GetResult();
            Client = new DocumentClient(
                _settings.AccountUri,
                authKey.Value,
                desiredConsistencyLevel: ConsistencyLevel.Session,
                serializerSettings: new JsonSerializerSettings()
                {
                    ContractResolver = new CamelCasePropertyNamesContractResolver()
                });

            var database = Client.CreateDatabaseQuery().Where(db => db.Id == _settings.Db).AsEnumerable().First();
            Collection = Client.CreateDocumentCollectionQuery(database.SelfLink).Where(c => c.Id == _settings.Collection).AsEnumerable().First();
            _feedOptions = new FeedOptions() { PopulateQueryMetrics = _settings.CollectMetrics };

            _logger.LogInformation($"Connected to doc db '{Collection.SelfLink}'");
        }

        public async Task SwitchCollection(string collectionName, params string[] partitionKeyPaths)
        {
            if (Collection.Id == collectionName)
            {
                return;
            }
            
            var database = Client.CreateDatabaseQuery().Where(db => db.Id == _settings.Db).AsEnumerable().First();
            Collection = Client.CreateDocumentCollectionQuery(database.SelfLink).Where(c => c.Id == collectionName).AsEnumerable().FirstOrDefault();
            if (Collection == null)
            {
                var partition = new PartitionKeyDefinition();
                if (partitionKeyPaths?.Any() == true)
                {
                    foreach (var keyPath in partitionKeyPaths)
                    {
                        partition.Paths.Add(keyPath);
                    }
                }
                else
                {
                    partition.Paths.Add("/id");
                }

                try
                {
                    await Client.CreateDocumentCollectionAsync(database.SelfLink, new DocumentCollection()
                    {
                        Id = collectionName,
                        PartitionKey = partition
                    }).ConfigureAwait(false);
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Failed to create collection");
                    throw;
                }
                
                Collection = Client.CreateDocumentCollectionQuery(database.SelfLink).Where(c => c.Id == collectionName).AsEnumerable().FirstOrDefault();
                _logger.LogInformation("Created collection {0} in {1}/{2}", collectionName, _settings.Account, _settings.Db);
            }

            _logger.LogInformation("Switched to collection {0}", collectionName);
        }

        public async Task<int> CountAsync(CancellationToken cancel = default)
        {
            var countQuery = @"SELECT VALUE COUNT(1) FROM c";
            var result = Client.CreateDocumentQuery<int>(
                Collection.DocumentsLink,
                new SqlQuerySpec()
                {
                    QueryText = countQuery,
                    Parameters = new SqlParameterCollection()
                },
                new FeedOptions()
                {
                    EnableCrossPartitionQuery = true
                }).AsDocumentQuery();

            int count = 0;
            while (result.HasMoreResults)
            {
                var batchSize = await result.ExecuteNextAsync<int>(cancel);
                count += batchSize.First();
            }
            return count;
        }

        public async Task DeleteObject(string id, CancellationToken cancel = default)
        {
            Ensure.That(id).IsNotNullOrWhiteSpace();

            try
            {
                Uri docUri = UriFactory.CreateDocumentUri(_settings.Db, _settings.Collection, id);
                await Client.DeleteDocumentAsync(docUri, cancellationToken: cancel);
            }
            catch (Exception e)
            {
                _logger.LogError(e, "Unable to Delete document. DatabaseName={0}, CollectionName={1}, DocumentId={2}, Exception={3}",
                    _settings.Db, _settings.Collection, id);
                throw;
            }
        }

        public async Task<IEnumerable<T>> Query<T>(SqlQuerySpec querySpec, FeedOptions feedOptions = null, CancellationToken cancel = default)
        {
            Ensure.That(querySpec).IsNotNull();

            try
            {
                var output = new List<T>();
                feedOptions ??= _feedOptions;
                feedOptions.PopulateQueryMetrics = _feedOptions.PopulateQueryMetrics;
                var query = Client
                    .CreateDocumentQuery<T>(Collection.SelfLink, querySpec, feedOptions)
                    .AsDocumentQuery();

                while (query.HasMoreResults)
                {
                    var response = await query.ExecuteNextAsync<T>(cancel);
                    output.AddRange(response);

                    if (_settings.CollectMetrics)
                    {
                        var queryMetrics = response.QueryMetrics;
                        foreach (var label in queryMetrics.Keys)
                        {
                            var queryMetric = queryMetrics[label];
                        }
                    }
                }
                //_logger.LogInformation("Total RU for {0}: {1}", nameof(Query), totalRequestUnits);

                return output;
            }
            catch (DocumentClientException e)
            {
                _logger.LogError(
                    e,
                    $"Unable to Query. DatabaseName={_settings.Db}, CollectionName={_settings.Collection}, Query={querySpec}, FeedOptions={feedOptions}");

                throw;
            }
                
        }

        public async Task<FeedResponse<T>> QueryInBatches<T>(SqlQuerySpec querySpec, FeedOptions feedOptions = null,
            CancellationToken cancel = default)
        {
            Ensure.That(querySpec).IsNotNull();

            try
            {
                feedOptions = feedOptions ?? _feedOptions;
                feedOptions.PopulateQueryMetrics = _feedOptions.PopulateQueryMetrics;
                var query = Client
                    .CreateDocumentQuery<T>(Collection.SelfLink, querySpec, feedOptions)
                    .AsDocumentQuery();

                if (query.HasMoreResults)
                {
                    var response = await query.ExecuteNextAsync<T>(cancel);
                    return response;
                }

                return null;
            }
            catch (DocumentClientException e)
            {
                _logger.LogError(
                    e,
                    $"Unable to Query. DatabaseName={_settings.Db}, CollectionName={_settings.Collection}, Query={querySpec}, FeedOptions={feedOptions}");

                throw;
            }
        }

        public async Task<T> ReadObject<T>(string id, CancellationToken cancel = default)
        {
            try
            {
                Uri docUri = UriFactory.CreateDocumentUri(_settings.Db, _settings.Collection, id);
                var response = await Client.ReadDocumentAsync<T>(docUri, cancellationToken: cancel);
                
                return response;
            }
            catch (Exception e)
            {
                _logger.LogError(e, "Unable to Read document. DatabaseName={0}, CollectionName={1}, DocumentId={2}, Exception={3}",
                    _settings.Db, _settings.Collection, id);
                throw;
            }
        }

        public async Task<string> UpsertObject<T>(T @object, RequestOptions requestOptions = null, CancellationToken cancel = default)
        {
            try
            {
                var response = await Client.UpsertDocumentAsync(Collection.SelfLink, @object, requestOptions, cancellationToken: cancel);
              
                return response.Resource.Id;
            }
            catch (Exception e)
            {
                _logger.LogError(e, "Unable to Upsert object. CollectionUrl={0}",
                    Collection.SelfLink);
                throw;
            }
        }

        public async Task ClearAll(CancellationToken cancel = default)
        {
            // this is slow, use sp to do bulk delete 
            try
            {
                var idsToDelete = new List<string>();
                var feedOptions = new FeedOptions(){EnableCrossPartitionQuery = true};
                var query = Client
                    .CreateDocumentQuery<string>(
                        Collection.SelfLink, 
                        new SqlQuerySpec("select value (c.id) from c"), 
                        feedOptions)
                    .AsDocumentQuery();

                _logger.LogInformation($"Reading existing docs in collection: {Collection.Id}");
                while (query.HasMoreResults)
                {
                    var response = await query.ExecuteNextAsync<string>(cancel);
                    if (response?.Any() == true)
                    {
                        idsToDelete.AddRange(response);
                        _logger.LogInformation($"Total docs read: {idsToDelete.Count}");
                    }
                }
                _logger.LogInformation($"Total docs in collection: {idsToDelete.Count}");

                if (idsToDelete.Count > 0)
                {
                    int totalDeleted = 0;
                    foreach (var id in idsToDelete)
                    {
                        await DeleteObject(id, cancel);
                        totalDeleted++;

                        if (totalDeleted % 100 == 0)
                        {
                            _logger.LogInformation($"deleted {totalDeleted} of {idsToDelete.Count} documents");
                        }
                    }
                    _logger.LogInformation($"Collection {Collection.Id} is cleared, total of {idsToDelete.Count} docs deleted");
                }
                else
                {
                    _logger.LogInformation($"Collection {Collection.Id} is already empty");
                }
            }
            catch (DocumentClientException e)
            {
                _logger.LogError(
                    e,
                    $"Unable to clear collection. DatabaseName={_settings.Db}, CollectionName={_settings.Collection}");

                throw;
            }
        }

        #region IDisposable Support
        private bool isDisposed; // To detect redundant calls

        private void Dispose(bool disposing)
        {
            if (!isDisposed)
            {
                if (disposing)
                {
                    Client.Dispose();
                }

                // TODO: free unmanaged resources (unmanaged objects) and override a finalizer below.
                // TODO: set large fields to null.

                isDisposed = true;
            }
        }

        // TODO: override a finalizer only if Dispose(bool disposing) above has code to free unmanaged resources.
        // ~DocDb() {
        //   // Do not change this code. Put cleanup code in Dispose(bool disposing) above.
        //   Dispose(false);
        // }

        // This code added to correctly implement the disposable pattern.
        public void Dispose()
        {
            // Do not change this code. Put cleanup code in Dispose(bool disposing) above.
            Dispose(true);
            // TODO: uncomment the following line if the finalizer is overridden above.
            // GC.SuppressFinalize(this);
        }
        #endregion
    }
}