// --------------------------------------------------------------------------------------------------------------------
// <copyright file="BlobClient.cs" company="Microsoft Corporation">
//   Copyright (c) 2020 Microsoft Corporation.  All rights reserved.
// </copyright>
// <summary>
// </summary>
// --------------------------------------------------------------------------------------------------------------------

using System;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Azure.Identity;
using Azure.Storage;
using Azure.Storage.Blobs;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace Common.Blob
{
    public class BlobClient : IBlobClient
    {
        private readonly ILogger<BlobClient> _logger;
        private readonly BlobContainerClient _containerClient;

        public BlobClient(
            IOptions<BlobStorageSettings> blobSettings,
            ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<BlobClient>();
            var settings = blobSettings.Value;
            _logger.LogInformation($"accessing blob (account={settings.Account}, container={settings.Container}) using default azure credential");
            _containerClient = new BlobContainerClient(new Uri(settings.ContainerEndpoint), new DefaultAzureCredential());
            _containerClient.CreateIfNotExists();
        }

        public async Task Upload(string blobFolder, string blobName, string blobContent, CancellationToken cancellationToken)
        {
            var blobPath = $"{blobFolder}/{blobName}";
            _logger.LogInformation($"uploading {blobPath}...");
            var blobClient = _containerClient.GetBlobClient(blobPath);
            var uploadResponse = await blobClient.UploadAsync(new MemoryStream(Encoding.UTF8.GetBytes(blobContent)), cancellationToken);
            _logger.LogInformation($"uploaded blob: {blobPath}");
        }

        public async Task Download(string blobFolder, string blobName, string localFolder, CancellationToken cancellationToken)
        {
            var blobPath = $"{blobFolder}/{blobName}";
            _logger.LogInformation($"downloading {blobPath}...");
            var blobClient = _containerClient.GetBlobClient(blobPath);
            var downloadInfo = await blobClient.DownloadAsync(cancellationToken);
            var filePath = Path.Combine(localFolder, blobName);
            await using var fs = File.OpenWrite(filePath);
            await downloadInfo.Value.Content.CopyToAsync(fs, cancellationToken);
            _logger.LogInformation($"blob written to {filePath}");
        }
    }
}