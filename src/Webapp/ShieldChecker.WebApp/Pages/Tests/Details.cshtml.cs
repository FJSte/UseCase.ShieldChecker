using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.EntityFrameworkCore;
using ShieldChecker.WebApp;
using ShieldChecker.WebApp.Models.Db;

namespace ShieldChecker.WebApp.Pages.Tests
{
    public class DetailsModel : PageModel
    {
        private readonly ShieldChecker.WebApp.ShieldCheckerContext _context;

        public DetailsModel(ShieldChecker.WebApp.ShieldCheckerContext context)
        {
            _context = context;
        }

        public TestDefinition Test { get; set; } = default!;

        public async Task<IActionResult> OnGetAsync(int? id)
        {
            if (id == null)
            {
                return NotFound();
            }

            var test = await _context.UseCaseTests.Include(u => u.CreatedBy).Include(u => u.ModifiedBy).FirstOrDefaultAsync(m => m.ID == id);
            if (test == null)
            {
                return NotFound();
            }
            else
            {
                Test = test;
            }
            return Page();
        }
        public async Task<IActionResult> OnGetSchedule(int id)
        {
            var test = await _context.UseCaseTests.FindAsync(id);
            if (test == null)
            {
                return Page();
            }
            TestJob job = new TestJob
            {
                Status = JobStatus.Queued,
                UseCase = test,
                Created = DateTime.UtcNow,
                Modified = DateTime.UtcNow,
                Result = JobResult.Undetermined,
                SchedulerLog = ""

            };
            _context.TestJobs.Add(job);
            await _context.SaveChangesAsync();
            return RedirectToPage("/Jobs/Index");

        }
    }
}
