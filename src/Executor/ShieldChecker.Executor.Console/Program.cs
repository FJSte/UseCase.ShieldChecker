using ShieldChecker.Executor.Core;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Console;
using Microsoft.Extensions.Logging.Debug;


using ILoggerFactory factory = LoggerFactory.Create(config =>
{
    config.AddDebug(); // Log to debug (debug window in Visual Studio or any debugger attached)
    config.AddConsole(); // Log to console (colored !)
                         // Add the custom FileLoggerProvider
    string logFilePath = Path.Combine(AppContext.BaseDirectory, "logs", "executor.log");
    Directory.CreateDirectory(Path.GetDirectoryName(logFilePath)!);
    config.AddProvider(new FileLoggerProvider(logFilePath));
});
ILogger<Engine> _logger = factory.CreateLogger<Engine>();

var builder = new ConfigurationBuilder()
    .SetBasePath(Directory.GetCurrentDirectory())
    .AddJsonFile("appsettings.json")
    .AddEnvironmentVariables();

IConfiguration _configuration = builder.Build();



_logger.LogInformation("Executor started");
string? azureFunctionUrl = _configuration["AzureFunctionUrl"];

if (string.IsNullOrEmpty(azureFunctionUrl))
{
    _logger.LogError("AzureFunctionUrl is not set in the configuration.");
    return;
}
else
{

    Engine e = new Engine(Environment.MachineName, azureFunctionUrl, _logger);
    String ExecutorOutput = "";
    bool StopExecution = false;
    int countOfTries = 10;
    while (!StopExecution && countOfTries > 0)
    {

        _logger.LogInformation($"Executor running at: {DateTimeOffset.Now}");
        ExecutorOutput += Environment.NewLine + ($"INFO: Executor running at: {DateTimeOffset.Now}");
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
                //Execution Successful
                StopExecution = true;
            }
            else
            {
                _logger.LogInformation("No job found.");
                ExecutorOutput += Environment.NewLine + "INFO: No job found.";
                JobUpdate update = new JobUpdate() { ExecutorOutput = ExecutorOutput, TestOutput = "", Status = 2 };
                await e.UpdateJobAsync(update);
            }
        }
        catch (Exception ex)
        {
            JobUpdate update = new JobUpdate() { ExecutorOutput = ExecutorOutput, TestOutput = "", Status = 7 };
            await e.UpdateJobAsync(update);
            _logger.LogError(ex, "Unknown Error");
        }

        await Task.Delay(30000);
        countOfTries -= 1;
    }
    _logger.LogInformation($"Executor ended at: {DateTimeOffset.Now}");
}

