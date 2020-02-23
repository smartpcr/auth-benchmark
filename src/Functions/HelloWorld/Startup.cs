using System;
using System.IO;
using System.Reflection;
using Common.Auth;
using Common.Blob;
using Common.DocDb;
using Common.KeyVault;
using Microsoft.Azure.Functions.Extensions.DependencyInjection;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.FileProviders;

namespace HelloWorld
{
    public class Startup : FunctionsStartup
    {
        public override void Configure(IFunctionsHostBuilder builder)
        {
            var services = builder.Services;

            // IConfiguration
            var webjobHome = Environment.GetEnvironmentVariable("AzureWebJobsScriptRoot");
            // TODO: k8s job home folder
            var home = Environment.GetEnvironmentVariable("HOME") == null
                ? Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location)
                : $"{Environment.GetEnvironmentVariable("HOME")}/site/wwwroot";
            var runtimeRootFolder = webjobHome ?? home;
            var config = new ConfigurationBuilder()
                .SetFileProvider(new PhysicalFileProvider(runtimeRootFolder))
                .AddJsonFile("appsettings.json", optional: false, reloadOnChange: false)
                .AddJsonFile($"appsettings.{Environment.GetEnvironmentVariable("AZURE_FUNCTIONS_ENVIRONMENT")}.json", optional: true, reloadOnChange: false)
                .AddJsonFile("local.settings.json", optional: true, reloadOnChange: false)
                .AddEnvironmentVariables()
                .Build();
            services.AddSingleton<IConfiguration>(config);

            // options
            services.Configure<AadSettings>(config.GetSection(nameof(AadSettings)));
            services.Configure<VaultSettings>(config.GetSection(nameof(VaultSettings)));
            services.Configure<BlobStorageSettings>(config.GetSection(nameof(BlobStorageSettings)));
            services.Configure<DocDbSettings>(config.GetSection(nameof(DocDbSettings)));
            services.AddOptions();

            // contract implementation
            services.AddTransient<IBlobClient, BlobClient>();
            services.AddTransient<IDocumentDbClient, DocumentDbClient>();
        }
    }
}
