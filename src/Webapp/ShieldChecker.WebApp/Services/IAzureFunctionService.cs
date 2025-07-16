namespace ShieldChecker.WebApp.Services
{
    public interface IAzureFunctionService
    {
        public Task<HttpResponseMessage> ImportAtomicTests();
    }
}
