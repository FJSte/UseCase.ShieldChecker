using Microsoft.Extensions.Logging;
using System;
using System.Diagnostics;
using System.Net.Http;
using System.Net.Http.Json;
using System.Runtime.InteropServices;
using System.Runtime.Versioning;
using System.Text.Json;
using System.Threading.Tasks;

namespace ShieldChecker.Executor.Core
{
    public class Engine
    {
        private readonly HttpClient httpClient = new HttpClient();
        private ILogger _logger;
        private readonly string _workerName;
        private readonly string _azureFunctionHostname;

        public Engine(string workerName, string azureFunctionHostname, ILogger<Engine> logger)
        {
            _logger = logger;
            _workerName = workerName;
            _azureFunctionHostname = azureFunctionHostname;
        }


        /// <summary>
        /// Fetches job details from the specified Azure Function URL for the current Worker.
        /// </summary>
        /// <returns>A TestDefinition object containing job details.</returns>
        public async Task<TestDefinition?> GetJobDetailsAsync()
        {
            string requestUrl = $"https://{_azureFunctionHostname}/api/Job?workername={_workerName}";
            _logger.LogTrace($"Fetching job details from URL: {requestUrl}");

            try
            {
                HttpResponseMessage response = await httpClient.GetAsync(requestUrl);
                if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
                {
                    return null;
                } else if (response.StatusCode == System.Net.HttpStatusCode.BadRequest)
                {
                    string responseContent = await response.Content.ReadAsStringAsync();
                    if(responseContent.Contains("Domain Controller is not yet ready, skip processing jobs"))
                    {
                        _logger.LogInformation("Domain Controller is not yet ready, skipping job processing.");
                        return null;
                    }
                    else
                    {
                        response.EnsureSuccessStatusCode();
                        string jsonResponse = await response.Content.ReadAsStringAsync();
                        _logger.LogInformation("Job details fetched successfully.");
                        var jobDetails = JsonSerializer.Deserialize<TestDefinition>(jsonResponse);

                        return jobDetails;
                    }
                }
                else
                {
                    response.EnsureSuccessStatusCode();

                    string jsonResponse = await response.Content.ReadAsStringAsync();
                    _logger.LogInformation("Job details fetched successfully.");
                    var jobDetails = JsonSerializer.Deserialize<TestDefinition>(jsonResponse);

                    return jobDetails;
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex,$"Error fetching job details: {ex.Message}");
                throw;
            }
        }

        public async Task UpdateJobAsync(JobUpdate update)
        {
            string requestUrl = $"https://{_azureFunctionHostname}/api/JobUpdater?workername={_workerName}";
            _logger.LogInformation($"Update job status: {requestUrl}");

            try
            {
                var jsonContent = JsonContent.Create(update);

                await jsonContent.LoadIntoBufferAsync(); // avoid chunked encoding

                HttpResponseMessage response = await httpClient.PostAsync(requestUrl, jsonContent);
                if (response.StatusCode != System.Net.HttpStatusCode.NotFound)
                {
                    response.EnsureSuccessStatusCode();
                }

            }
            catch (Exception ex)
            {
                _logger.LogError(ex, $"Error updating job: {ex.Message}");
                throw;
            }
        }


        /// <summary>
        /// Executes the scripts defined in the job in the order: Prerequisites -> Test -> Cleanup.
        /// </summary>
        /// <param name="jobDefinition">The job definition containing script details.</param>
        public void ExecuteJobScripts(TestDefinition jobDefinition)
        {
            if (jobDefinition == null)
                throw new ArgumentNullException(nameof(jobDefinition));

            _logger.LogInformation($"Starting execution of job: {jobDefinition.Name}");

            string shell, scriptExtension;

            // Determine the shell and script extension based on the operating system
            switch (jobDefinition.OperatingSystem)
            {
                case OperatingSystem.Windows:
                    shell = "powershell.exe";
                    scriptExtension = ".ps1";
                    break;

                case OperatingSystem.Linux:
                    shell = "pwsh";
                    scriptExtension = ".ps1";
                    break;

                default:
                    throw new NotSupportedException("Unsupported operating system.");
            }

            // Execute the scripts in the order: Prerequisites -> Test -> Cleanup
            _logger.LogInformation("Executing prerequisites script...");
            ExecuteScript(shell, jobDefinition.ScriptPrerequisites, scriptExtension, jobDefinition.Username, jobDefinition.Password, jobDefinition.Domain);

            _logger.LogInformation("Executing test script...");
            ExecuteScript(shell, jobDefinition.ScriptTest, scriptExtension, jobDefinition.Username, jobDefinition.Password, jobDefinition.Domain);

            _logger.LogInformation("Executing cleanup script...");
            ExecuteScript(shell, jobDefinition.ScriptCleanup, scriptExtension, jobDefinition.Username, jobDefinition.Password, jobDefinition.Domain);

            _logger.LogInformation("Job execution completed successfully.");
        }

        /// <summary>
        /// Executes a script using the specified shell and optional credentials.
        /// </summary>
        /// <param name="shell">The shell to use for execution (e.g., PowerShell or Bash).</param>
        /// <param name="scriptContent">The content of the script to execute.</param>
        /// <param name="scriptExtension">The file extension for the script (e.g., .ps1 or .sh).</param>
        /// <param name="username">Optional username for executing the script under specific credentials.</param>
        /// <param name="password">Optional password for executing the script under specific credentials.</param>
        /// <param name="domain">Optional domain for the user credentials.</param>
        private void ExecuteScript(string shell, string scriptContent, string scriptExtension, string? username = null, string? password = null, string? domain = null)
        {
            bool isWindows = RuntimeInformation.IsOSPlatform(OSPlatform.Windows);

            if (string.IsNullOrWhiteSpace(scriptContent))
            {
                _logger.LogInformation("No script content provided. Skipping execution.");
                return;
            }

            // Create a temporary file for the script
            string tempScriptPath = System.IO.Path.Combine(System.IO.Path.GetTempPath(), Guid.NewGuid() + scriptExtension);
            if (isWindows)
            {
                // Create Folder if not exists
                if (!System.IO.Directory.Exists("c:\\TestEngine"))
                {
                    System.IO.Directory.CreateDirectory("c:\\TestEngine");
                }
                tempScriptPath = System.IO.Path.Combine("c:\\TestEngine", Guid.NewGuid() + scriptExtension);
            } 
            System.IO.File.WriteAllText(tempScriptPath, scriptContent);
            _logger.LogInformation($"Temporary script file created at: {tempScriptPath}");

            if (shell.Equals("powershell.exe"))
            {
                tempScriptPath = "-ExecutionPolicy Bypass -File \"" + tempScriptPath + "\"";
            }
            if (shell.Equals("pwsh"))
            {
                tempScriptPath = "-ExecutionPolicy Bypass -File \"" + tempScriptPath + "\"";
            }

            try
            {
                // Configure the process to execute the script
                var processStartInfo = new ProcessStartInfo
                {
                    FileName = shell,
                    Arguments = tempScriptPath,
                    UseShellExecute = false, // Must be false to use credentials
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true

                };

                if (isWindows)
                {
                    // If username and password are provided, set them
                    if (!string.IsNullOrWhiteSpace(username) && !string.IsNullOrWhiteSpace(password))
                    {
                        processStartInfo.UserName = username;
                        processStartInfo.Password = ConvertToSecureString(password);
                        processStartInfo.Domain = domain;
                        processStartInfo.UseShellExecute = false;
                        _logger.LogInformation($"Executing script as user: {username}");
                    }
                }

                Process process = new Process();
                process.StartInfo = processStartInfo;
                
                process.OutputDataReceived += (sender, e) =>
                {
                    if (!string.IsNullOrEmpty(e.Data))
                    {
                        _logger.LogInformation($"PSOUT: {e.Data}");
                    }
                };
                process.ErrorDataReceived += (sender, e) =>
                {
                    if (!string.IsNullOrEmpty(e.Data))
                    {
                        _logger.LogError($"PSERR: {e.Data}");
                    }
                };
                process.Start();
                process.BeginOutputReadLine();
                process.BeginErrorReadLine();
                _logger.LogInformation("Script execution started...");
                        
                process.WaitForExit(new TimeSpan(0, 30, 0)); // Wait for up to 30 minutes
                if (!process.HasExited)
                {
                    _logger.LogWarning("Script execution timed out after 15 minutes. Killing the process.");
                    process.Kill();
                    process.WaitForExit(new TimeSpan(0, 1, 0)); // Ensure the process has exited
                }
                else
                {
                    _logger.LogInformation("Script execution completed.");
                    if (process.ExitCode != 0)
                    {
                        throw new InvalidOperationException($"Script execution failed with exit code {process.ExitCode}.");
                    }
                    else
                    {
                        _logger.LogInformation("Script executed successfully.");
                    }
                }   
                    
            } catch (Exception ex) {
                _logger.LogError(ex, ex.Message);
            } finally
            {
                // Clean up the temporary script file
                if (System.IO.File.Exists(tempScriptPath))
                {
                    System.IO.File.Delete(tempScriptPath);
                    _logger.LogInformation($"Temporary script file deleted: {tempScriptPath}");
                }
            }
        }

        /// <summary>
        /// Converts a plain string to a SecureString.
        /// </summary>
        /// <param name="str">The plain string to convert.</param>
        /// <returns>A SecureString representation of the input string.</returns>
        private System.Security.SecureString ConvertToSecureString(string str)
        {
            var secureString = new System.Security.SecureString();
            foreach (char c in str)
            {
                secureString.AppendChar(c);
            }
            secureString.MakeReadOnly();
            return secureString;
        }
    }
}
