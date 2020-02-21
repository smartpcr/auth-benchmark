// --------------------------------------------------------------------------------------------------------------------
// <copyright file="BlobStoreSettings.cs" company="Microsoft">
// </copyright>
// <summary>
//  The ElectricalDatacenterHealthService
// </summary>
// --------------------------------------------------------------------------------------------------------------------

namespace BlobStore
{
    public class BlobStoreSettings
    {
        /// <summary>
        /// secret name used to retrieve connection string, when it's not specified, credential is set to use aad app
        /// </summary>
        public string ConnectionName { get; set; }

        public string AccountName { get; set; }
        
        public string ContainerName { get; set; }

        public string ContainerEndpoint => $"https://{AccountName}.blob.core.windows.net/{ContainerName}";
    }
}