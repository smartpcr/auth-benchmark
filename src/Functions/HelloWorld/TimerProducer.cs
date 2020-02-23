using System;
using System.Diagnostics;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Common.Blob;
using Microsoft.Azure.WebJobs;
using Microsoft.Azure.WebJobs.Host;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;

namespace HelloWorld
{
    /// <summary>
    /// write 100 records per second to blob storage
    /// </summary>
    public static class TimerProducer
    {
        private static int _sequence = 0;
        private static readonly SemaphoreSlim _semaphore = new SemaphoreSlim(0, 1);

        [FunctionName("TimerProducer")]
        public static void Run(
            [TimerTrigger("*/1 * * * * *")]TimerInfo myTimer,
            ILogger log,
            IBlobClient blobClient)
        {
            log.LogInformation($"C# Timer trigger function started at: {DateTime.Now}");
            var watch = Stopwatch.StartNew();
            var random = new Random(DateTime.UtcNow.Millisecond);
            foreach (var i in Enumerable.Range(1, 100))
            {
                _semaphore.Wait();
                Interlocked.Increment(ref _sequence);
                log.LogInformation($"writing {i}...");
                var telemetry = new
                {
                    Id = Guid.NewGuid().ToString(),
                    TimeStamp = DateTime.UtcNow,
                    Temperature = random.Next(0, 200),
                    Amps = random.Next(0, 1000),
                    Volt = random.Next(0, 1200),
                    Sequence = _sequence
                };
                _semaphore.Release();

                var json = JsonConvert.SerializeObject(telemetry);
                var blobFolder = telemetry.TimeStamp.ToString("yyyy/MM/dd/HH/mm");
                try
                {
                    Task.Run(() =>
                        blobClient.Upload(blobFolder, $"{telemetry.Sequence}.json", json, new CancellationToken()));
                }
                catch (Exception ex)
                {
                    log.LogError(100, ex, $"Failed to store data to blob: sequence={telemetry.Sequence}");
                }
            }
            log.LogInformation($"Timer trigger function finished, lapse: {watch.Elapsed}");
        }
    }
}
