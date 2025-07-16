using ShieldChecker.Executor.Core;
using Microsoft.Extensions.Logging;

namespace ShieldChecker.Executor.Service
{
    public class Worker : BackgroundService
    {
        private readonly ILogger<Engine> _logger;
        private readonly IConfiguration _configuration;

        public Worker(ILogger<Engine> logger, IConfiguration configuration)
        {
            _logger = logger;
            _configuration = configuration;
        }
        

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            try { 
                _logger.LogInformation("Worker started");
                string? azureFunctionUrl = _configuration["AzureFunctionUrl"];
            
                if (string.IsNullOrEmpty(azureFunctionUrl))
                {
                    _logger.LogError("AzureFunctionUrl is not set in the configuration.");
                    return;
                }
                else
                {

                    Engine e = new Engine(Environment.MachineName, azureFunctionUrl, _logger);
                    
                    while (!stoppingToken.IsCancellationRequested)
                    {
                        String ExecutorOutput = "";
                        _logger.LogTrace($"Worker running at: {DateTimeOffset.Now}");
                        ExecutorOutput += Environment.NewLine + ($"INFO: Worker running at: {DateTimeOffset.Now}");
                        try
                        {
                            // Fetch job details
                            var jobDetails = await e.GetJobDetailsAsync();

                            if (jobDetails != null)
                            {
                                // Execute the job scripts
                                e.ExecuteJobScripts(jobDetails);
                                // load content of log file to a string
                                string logFilePath = Path.Combine(AppContext.BaseDirectory, "logs", "executor.log");
                                string TestOutput = File.ReadAllText(logFilePath);
                            
                                JobUpdate update = new JobUpdate() { ExecutorOutput = ExecutorOutput, TestOutput = TestOutput, Status = 2 };
                                await e.UpdateJobAsync(update);
                            }
                            else
                            {
                                _logger.LogTrace("No job found.");
                                ExecutorOutput += Environment.NewLine + "INFO: No job found.";
                                
                            }
                        }
                        catch (Exception ex)
                        {
                            JobUpdate update = new JobUpdate() { ExecutorOutput = ExecutorOutput, TestOutput = "", Status = 7 };
                            await e.UpdateJobAsync(update);
                            _logger.LogError(ex, "Unknown Error");
                        }

                        await Task.Delay(30000, stoppingToken);
                    }
                }
            }
            catch (OperationCanceledException)
            {
                // When the stopping token is canceled, for example, a call made from services.msc,
                // we shouldn't exit with a non-zero exit code. In other words, this is expected...
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "{Message}", ex.Message);

                // Terminates this process and returns an exit code to the operating system.
                // This is required to avoid the 'BackgroundServiceExceptionBehavior', which
                // performs one of two scenarios:
                // 1. When set to "Ignore": will do nothing at all, errors cause zombie services.
                // 2. When set to "StopHost": will cleanly stop the host, and log errors.
                //
                // In order for the Windows Service Management system to leverage configured
                // recovery options, we need to terminate the process with a non-zero exit code.
                Environment.Exit(1);
            }
        }
    }
}
