using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace Common.Config
{
    public static class OptionsBuilder
    {
        public static IServiceCollection ConfigureOptions<T>(this IServiceCollection services, IConfiguration configuration) where T : class, new()
        {
            return services;
        }
    }
}