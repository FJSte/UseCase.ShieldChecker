using Microsoft.Extensions.Logging;
using System;
using System.IO;

namespace ShieldChecker.Executor.Core
{
    public class FileLoggerProvider : ILoggerProvider
    {
        private readonly string _logFilePath;

        public FileLoggerProvider(string logFilePath)
        {
            _logFilePath = logFilePath;
        }

        public ILogger CreateLogger(string categoryName)
        {
            return new FileLogger(categoryName, _logFilePath);
        }

        public void Dispose()
        {
            // No resources to dispose
        }
    }
}
