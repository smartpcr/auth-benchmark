// --------------------------------------------------------------------------------------------------------------------
// <copyright file="AadAuthBuilder.cs" company="Microsoft">
// </copyright>
// <summary>
//  The ElectricalDatacenterHealthService
// </summary>
// --------------------------------------------------------------------------------------------------------------------

using System;
using System.IO;
using System.Security.Cryptography.X509Certificates;
using System.Threading.Tasks;
using Azure.Core;
using Azure.Identity;
using Microsoft.Identity.Client;

namespace Common.Auth
{
    public class AadAuthBuilder
    {
        private readonly AadSettings _settings;
        
        public AadAuthBuilder(AadSettings settings)
        {
            _settings = settings;
        }

        public TokenCredential GetTokenCredential()
        {
            if (!string.IsNullOrEmpty(_settings.ClientSecretFile))
            {
                var clientSecretFile = GetSecretOrCertFile(_settings.ClientSecretFile);
                var clientSecret = File.ReadAllText(clientSecretFile);
                return new ClientSecretCredential(_settings.TenantId, _settings.ClientId, clientSecret);
            }
            else
            {
                var clientCertFile = GetSecretOrCertFile(_settings.ClientCertFile);
                var certificate = new X509Certificate2(clientCertFile);
                return new ClientCertificateCredential(_settings.TenantId, _settings.ClientId, certificate);
            }
        }

        public async Task<string> GetAccessToken()
        {
            IConfidentialClientApplication app = null;
            if (!string.IsNullOrEmpty(_settings.ClientSecretFile))
            {
                var clientSecretFile = GetSecretOrCertFile(_settings.ClientSecretFile);
                var clientSecret = File.ReadAllText(clientSecretFile);
                app = ConfidentialClientApplicationBuilder.Create(_settings.ClientId).WithClientSecret(clientSecret).Build();
            }
            else
            {
                var clientCertFile = GetSecretOrCertFile(_settings.ClientCertFile);
                var certificate = new X509Certificate2(clientCertFile);
                app = ConfidentialClientApplicationBuilder.Create(_settings.ClientId).WithCertificate(certificate).Build();
            }
            
            var authResult = await app.AcquireTokenForClient(_settings.Scopes).ExecuteAsync();
            if (authResult == null)
                throw new InvalidOperationException("Failed to obtain the JWT token");
            return authResult.AccessToken;
        }
        
        /// <summary>
        /// fallback: secretFile --> ~/.secrets/secretFile --> /tmp/.secrets/secretFile
        /// </summary>
        /// <param name="secretOrCertFile"></param>
        /// <returns></returns>
        /// <exception cref="Exception"></exception>
        private static string GetSecretOrCertFile(string secretOrCertFile)
        {
            if (!File.Exists(secretOrCertFile))
            {
                var homeFolder = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
                secretOrCertFile = Path.Combine(homeFolder, ".secrets", secretOrCertFile);

                if (!File.Exists(secretOrCertFile))
                {
                    secretOrCertFile = Path.Combine("/tmp/.secrets", secretOrCertFile);
                }
            }
            if (!File.Exists(secretOrCertFile))
            {
                throw new System.Exception($"unable to find client secret/cert file: {secretOrCertFile}");
            }

            return secretOrCertFile;
        }
    }
}