// --------------------------------------------------------------------------------------------------------------------
// <copyright file="BlobStoreClient.cs" company="Microsoft">
// </copyright>
// <summary>
//  The ElectricalDatacenterHealthService
// </summary>
// --------------------------------------------------------------------------------------------------------------------

using System;
using System.Threading;
using System.Threading.Tasks;
using Azure.Identity;
using Azure.Storage.Blobs;
using Common.Auth;
using Common.KeyVault;
using Microsoft.Azure.KeyVault;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Microsoft.Rest;

namespace BlobStore
{
    public class BlobStoreClient
    {
        private readonly BlobStoreSettings _blobSettings;
        private readonly VaultSettings _vaultSettings;
        private readonly AadSettings _aadSettings;
        private readonly ILogger<BlobStoreClient> _logger;
        private readonly BlobContainerClient _client;

        public BlobStoreClient(
            IConfiguration configuration,
            IKeyVaultClient kv,
            ILoggerFactory loggerFactory)
        {
            _blobSettings = new BlobStoreSettings();
            configuration.Bind(nameof(BlobStoreSettings), _blobSettings);
            _vaultSettings = new VaultSettings();
            configuration.Bind(nameof(VaultSettings), _vaultSettings);
            _aadSettings = new AadSettings();
            configuration.Bind(nameof(AadSettings), _aadSettings);
            _logger = loggerFactory.CreateLogger<BlobStoreClient>();
            
            if (string.IsNullOrEmpty(_blobSettings.ContainerName))
            {
                _logger?.LogInformation($"creating blob client using aad credential");
                _client = CreateClientUsingAadAuth();
            }
            else
            {
                _logger?.LogInformation($"creating blob client using conn string stored in kv");
                _client = CreateClientUsingConnStr(kv).Result;
            }
        }

        private async Task<BlobContainerClient> CreateClientUsingConnStr(IKeyVaultClient kv)
        {
            var connStr = await kv.GetSecretAsync(_vaultSettings.VaultUrl, _blobSettings.ConnectionName);
            return new BlobContainerClient(connStr.Value, _blobSettings.ContainerName);
        }

        private BlobContainerClient CreateClientUsingAadAuth()
        {
            var aadAuthBuilder = new AadAuthBuilder(_aadSettings);
            return new BlobContainerClient(new Uri(_blobSettings.ContainerEndpoint), aadAuthBuilder.GetTokenCredential());
        }

        public async Task SyncFilesToCloud(string folderPath, CancellationToken cancellationToken)
        {
            
            throw new NotImplementedException();
        }
    }
}