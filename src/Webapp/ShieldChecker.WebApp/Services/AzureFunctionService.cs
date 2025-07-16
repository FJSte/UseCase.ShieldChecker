using ShieldChecker.WebApp.Pages.FirstRun;

namespace ShieldChecker.WebApp.Services
{
    public class AzureFunctionService : IAzureFunctionService
    {
        private readonly HttpClient _httpClient;
        private readonly ILogger<AzureFunctionService> _logger;
        private readonly IConfiguration _configuration;

        public AzureFunctionService(IHttpClientFactory httpClient, ILogger<AzureFunctionService> logger, IConfiguration configuration)
        {
            _httpClient = httpClient.CreateClient();
            _logger = logger;
            _configuration = configuration;
        }
        public async Task<HttpResponseMessage> ImportAtomicTests()
        {
            _httpClient.Timeout = new TimeSpan(0, 10, 0);
            var response = await _httpClient.GetAsync(($"https://{_configuration["SC_FUN_HOSTNAME"]}/api/ImportTests?code={_configuration["SC_FUN_KEY"]}"));
            if (response.IsSuccessStatusCode)
            {
                return response;
            }
            else
            {
                _logger.LogError("Failed to import Atomic Tests");
                return response;
            }
        }
    }
}
