using System;
using System.Diagnostics;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Common.Blob;
using Microsoft.Azure.WebJobs;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;

namespace HelloWorld
{
    /// <summary>
    /// write 100 records per second to blob storage
    /// </summary>
    public class TimerProducer
    {
        private readonly IBlobClient _blobClient;
        private static int _sequence = 0;

        public TimerProducer(IBlobClient blobClient)
        {
            _blobClient = blobClient;
        }

        [FunctionName("TimerProducer")]
        public async Task Run(
            [TimerTrigger("* * * * * *")]TimerInfo myTimer,
            ILogger log)
        {
            log.LogInformation($"C# Timer trigger function started at: {DateTime.Now}");
            var watch = Stopwatch.StartNew();
            var random = new Random(DateTime.UtcNow.Millisecond);
            foreach (var i in Enumerable.Range(1, 100))
            {
                log.LogInformation($"writing {i}...");
                var telemetry = new
                {
                    Id = Guid.NewGuid().ToString(),
                    TimeStamp = DateTime.UtcNow,
                    Temperature = random.Next(0, 200),
                    Amps = random.Next(0, 1000),
                    Volt = random.Next(0, 1200),
                    Sequence = Interlocked.Increment(ref _sequence)
                };

                var json = JsonConvert.SerializeObject(telemetry);
                var blobFolder = telemetry.TimeStamp.ToString("yyyy/MM/dd/HH/mm");
                try
                {
                    await _blobClient.Upload(blobFolder, $"{telemetry.Sequence}.json", json, new CancellationToken());
                }
                catch (Exception ex)
                {
                    log.LogError(ex, "Failed to push data to blob");
                }
            }
            log.LogInformation($"Timer trigger function finished, lapse: {watch.Elapsed}");
        }
    }
}
