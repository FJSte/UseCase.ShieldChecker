using ShieldChecker.Executor.Service;
using ShieldChecker.Executor.Core;

var builder = Host.CreateApplicationBuilder(args);

builder.Services.AddWindowsService();

builder.Services.AddHostedService<Worker>()
    .AddLogging(config =>
    {
        config.AddDebug(); // Log to debug (debug window in Visual Studio or any debugger attached)
        config.AddConsole(); // Log to console (colored !)
                             // Add the custom FileLoggerProvider
                             
        string logFilePath = Path.Combine(AppContext.BaseDirectory, "logs", "executor.log");
        Directory.CreateDirectory(Path.GetDirectoryName(logFilePath)!);
        config.AddProvider(new FileLoggerProvider(logFilePath));
    });
builder.Configuration
    .SetBasePath(AppContext.BaseDirectory)
    .AddJsonFile("appsettings.json")
    .AddEnvironmentVariables()
    .Build();


var host = builder.Build();
host.Run();
