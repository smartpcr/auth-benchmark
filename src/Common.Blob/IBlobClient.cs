using System;
using System.Threading;
using System.Threading.Tasks;

namespace Common.Blob
{
    public interface IBlobClient
    {
        Task Upload(string blobFolder, string blobName, string blobContent, CancellationToken cancellationToken);
        Task Download(string blobFolder, string blobName, string localFolder, CancellationToken cancellationToken);
    }
}