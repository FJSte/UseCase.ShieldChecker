using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.EntityFrameworkCore;
using ShieldChecker.WebApp;
using ShieldChecker.WebApp.Models.Db;
using ShieldChecker.WebApp.Helper;
using static System.Net.Mime.MediaTypeNames;

namespace ShieldChecker.WebApp.Pages.Jobs
{
    public class IndexModel : PageModel
    {
        private readonly ShieldChecker.WebApp.ShieldCheckerContext _context;
        private readonly IConfiguration _configuration;

        public IndexModel(ShieldChecker.WebApp.ShieldCheckerContext context, IConfiguration configuration)
        {
            _context = context;
            _configuration = configuration;
        }
        public PaginatedList<TestJob> TestJob { get; set; }

        public async Task OnGetAsync(int? pageIndex)
        {
       

            IQueryable<TestJob> testJobsIQ = from s in _context.TestJobs
                                                 select s;

            var pageSize = _configuration.GetValue("PageSize", 25);
            TestJob = await PaginatedList<TestJob>.CreateAsync(testJobsIQ.AsNoTracking().OrderByDescending(t => t.Created).Include(u => u.UseCase).Select(t => new TestJob() { ID = t.ID, UseCaseID = t.UseCaseID, UseCase = t.UseCase, Modified = t.Modified, WorkerName = t.WorkerName, Status = t.Status, Result = t.Result }), pageIndex ?? 1, pageSize);
        }
        
    }
}
