using ShieldChecker.WebApp.Models.Db;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.EntityFrameworkCore;

namespace ShieldChecker.WebApp.Pages.Jobs
{
    public class DownloadRdpModel : PageModel
    {
        private readonly ShieldChecker.WebApp.ShieldCheckerContext _context;
        private readonly IConfiguration _config;

        public DownloadRdpModel(ShieldChecker.WebApp.ShieldCheckerContext context, IConfiguration config)
        {
            _context = context;
            _config = config;
        }

        public async Task<IActionResult> OnGetAsync(int? id)
        {
            if (id == null)
            {
                return NotFound();
            }

            var testJob = await _context.TestJobs.Select(t => new TestJob() { ID=t.ID,WorkerName=t.WorkerName,WorkerRemoteIP=t.WorkerRemoteIP,Status=t.Status,Result=t.Result })
                .FirstOrDefaultAsync(m => m.ID == id);
            if (testJob == null)
            {
                return NotFound();
            }

            var stream = GenerateStreamFromString("full address:s:" + testJob.WorkerRemoteIP + "\r\nusername:s:" + _config["AdminUsername"] + "\r\ndomain:s:" + testJob.WorkerName);

            stream.Position = 0;
            string filename = testJob.WorkerName ?? "shieldchecker";

            return File(stream, "application/octet-stream", filename + ".rdp");


        }
        public static Stream GenerateStreamFromString(string s)
        {
            var stream = new MemoryStream();
            var writer = new StreamWriter(stream);
            writer.Write(s);
            writer.Flush();
            stream.Position = 0;
            return stream;
        }
    }
}
