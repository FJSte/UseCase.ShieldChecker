using Microsoft.Extensions.Logging;
using System;
using System.IO;

namespace ShieldChecker.Executor.Core
{
    public class FileLogger : ILogger
    {
        private readonly string _filePath;
        private readonly string _categoryName;
        private static readonly object _lock = new object();
        private const long MaxFileSizeInBytes = 1 * 1024 * 1024; // 1MB

        public FileLogger(string categoryName, string filePath)
        {
            _categoryName = categoryName;
            _filePath = filePath;
        }

        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;

        public bool IsEnabled(LogLevel logLevel) => logLevel != LogLevel.None;

        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter)
        {
            if (!IsEnabled(logLevel))
                return;

            if (formatter == null)
                throw new ArgumentNullException(nameof(formatter));

            string message = formatter(state, exception);
            if (string.IsNullOrWhiteSpace(message) && exception == null)
                return;

            string logRecord = $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} - {logLevel} - {message}";
            if (exception != null)
            {
                logRecord += Environment.NewLine + exception;
            }

            lock (_lock)
            {
                EnsureLogFileRolling();
                File.AppendAllText(_filePath, logRecord + Environment.NewLine);
            }
        }

        /// <summary>
        /// Ensures log file rolling when the file exceeds the maximum size.
        /// </summary>
        private void EnsureLogFileRolling()
        {
            if (File.Exists(_filePath))
            {
                FileInfo fileInfo = new FileInfo(_filePath);
                if (fileInfo.Length > MaxFileSizeInBytes)
                {
                    string rolledFilePath = Path.Combine(Path.GetDirectoryName(_filePath)!, Path.GetFileNameWithoutExtension(_filePath) + "_2" + Path.GetExtension(_filePath));

                    // Delete the rolled file if it already exists
                    if (File.Exists(rolledFilePath))
                    {
                        File.Delete(rolledFilePath);
                    }

                    // Rename the current log file to the rolled file
                    File.Move(_filePath, rolledFilePath);
                }
            }
        }
    }
}
