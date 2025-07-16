using ShieldChecker.WebApp.Models.Db;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.EntityFrameworkCore;

namespace ShieldChecker.WebApp.Pages.Jobs
{
    public class RerunJobModel : PageModel
    {
        private readonly ShieldChecker.WebApp.ShieldCheckerContext _context;

        public RerunJobModel(ShieldChecker.WebApp.ShieldCheckerContext context)
        {
            _context = context;
        }

        [BindProperty]
        public TestJob TestJob { get; set; } = default!;

        public async Task<IActionResult> OnGetAsync(int? id)
        {
            if (id == null)
            {
                return NotFound();
            }

#pragma warning disable CS8601 // Possible null reference assignment.
            TestJob = await _context.TestJobs.Include(u => u.UseCase).Select(t => new TestJob { ID = t.ID, UseCase = t.UseCase }).FirstOrDefaultAsync(m => m.ID == id);
#pragma warning restore CS8601 // Possible null reference assignment.
            if (TestJob == null)
            {
                return NotFound();
            }

            return Page();
        }

        public async Task<IActionResult> OnPostAsync()
        {
#pragma warning disable CS8601 // Possible null reference assignment.
            TestJob = await _context.TestJobs.Include(u => u.UseCase).Select(t => new TestJob{ ID=t.ID,UseCase=t.UseCase }).FirstOrDefaultAsync(m => m.ID == TestJob.ID);
#pragma warning restore CS8601 // Possible null reference assignment.
            if (TestJob == null)
            {
                return NotFound();
            }
            TestJob job = new TestJob
            {
                Status = JobStatus.Queued,
                UseCase = TestJob.UseCase,
                Created = DateTime.UtcNow,
                Modified = DateTime.UtcNow,
                Result = JobResult.Undetermined,
                SchedulerLog = ""
                
            };
            _context.TestJobs.Add(job);
            try
            {
                await _context.SaveChangesAsync();
            }
            catch (DbUpdateConcurrencyException)
            {

            }

            return RedirectToPage("./Index");
        }
    }
}
