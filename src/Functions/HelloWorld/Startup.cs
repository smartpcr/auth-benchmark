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
            SetupDI(builder.Services);
        }

        private void SetupDI(IServiceCollection services)
        {
            // IConfiguration
            var webjobHome = Environment.GetEnvironmentVariable("AzureWebJobsScriptRoot");
            // TODO: k8s job home folder
            var home = Environment.GetEnvironmentVariable("HOME") == null
                ? Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location)
                : $"{Environment.GetEnvironmentVariable("HOME")}/site/wwwroot";
            var runtimeRootFolder = webjobHome ?? home;
            Console.WriteLine($"using base folder: {runtimeRootFolder}");

            var config = new ConfigurationBuilder()
                .SetFileProvider(new PhysicalFileProvider(runtimeRootFolder))
                .AddJsonFile("appsettings.json", optional: false, reloadOnChange: false)
                .AddJsonFile($"appsettings.{Environment.GetEnvironmentVariable("AZURE_FUNCTIONS_ENVIRONMENT")}.json", optional: true, reloadOnChange: false)
                .AddJsonFile("local.settings.json", optional: true, reloadOnChange: false)
                .AddEnvironmentVariables()
                .Build();
            services.AddSingleton<IConfiguration>(config);
            Console.WriteLine("registered configuration");

            // options
            services.ConfigureOptions<AadSettings>();
            services.ConfigureOptions<VaultSettings>();
            services.ConfigureOptions<BlobStorageSettings>();
            services.ConfigureOptions<DocDbSettings>();
            services.AddOptions();

            // contract implementation
            Console.WriteLine("registering blob client...");
            services.AddSingleton<IBlobClient, BlobClient>();
            Console.WriteLine("registered blob client");
            services.AddSingleton<IDocumentDbClient, DocumentDbClient>();
        }

        private void ConfigureOptions<T>(IServiceCollection services) where T: class, new()
        {
            services.AddOptions<T>()
                .Configure<IConfiguration>((settings, configuration) =>
                {
                    configuration.GetSection(typeof(T).Name).Bind(settings);
                });
        }
    }
}
