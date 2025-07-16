namespace ShieldChecker.WebApp.Models.Db
{
    public class ViewReviewTestJob
    {
        public int ID { get; set; }
        public DateTime Modified { get; set; }
        public JobResult Result { get; set; }
        public string? ReviewResult { get; set; }
        public string? WorkerRemoteIP { get; set; }
        public OperatingSystem OperatingSystem { get; set; }
        public string? UseCaseName { get; set; }
    }
    
}
