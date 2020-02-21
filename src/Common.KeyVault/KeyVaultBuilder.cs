// --------------------------------------------------------------------------------------------------------------------
// <copyright file="Allocation.cs" company="Microsoft Corporation">
//   Copyright (c) 2020 Microsoft Corporation.  All rights reserved.
// </copyright>
// <summary>
// </summary>
// --------------------------------------------------------------------------------------------------------------------

using System;
using System.IO;
using System.Security.Cryptography.X509Certificates;
using System.Threading.Tasks;
using Common.Auth;
using Microsoft.Azure.KeyVault;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;

namespace Common.KeyVault
{
    public static class KeyVaultBuilder
    {
        public static IServiceCollection AddKeyVault(this IServiceCollection services, IConfiguration configuration)
        {
            var vaultSettings = new VaultSettings();
            configuration.Bind(nameof(VaultSettings), vaultSettings);
            
            var aadSettings = new AadSettings();
            configuration.Bind(nameof(AadSettings), aadSettings);
            var authBuilder = new AadAuthBuilder(aadSettings);
            
            var loggerFactory = services.BuildServiceProvider().GetService<ILoggerFactory>();
            var logger = loggerFactory?.CreateLogger<VaultSettings>();
            logger?.LogInformation($"retrieving vault settings: vaultName={vaultSettings.VaultName}");

            async Task<string> AuthCallback(string authority, string resource, string scope) => await authBuilder.GetAccessToken();
            var kvClient = new KeyVaultClient(AuthCallback);
            services.AddSingleton<IKeyVaultClient>(kvClient);

            return services;
        }

        
    }
}