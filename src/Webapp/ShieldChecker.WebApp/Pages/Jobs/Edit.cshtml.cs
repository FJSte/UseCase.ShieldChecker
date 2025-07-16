using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.AspNetCore.Mvc.Rendering;
using Microsoft.EntityFrameworkCore;
using ShieldChecker.WebApp;
using ShieldChecker.WebApp.Models.Db;
using ShieldChecker.WebApp.Models.View;

namespace ShieldChecker.WebApp.Pages.Jobs
{
    public class EditModel : PageModel
    {
        private readonly ShieldChecker.WebApp.ShieldCheckerContext _context;

        public EditModel(ShieldChecker.WebApp.ShieldCheckerContext context)
        {
            _context = context;
        }

        [BindProperty]
        public ViewEditTestJob TestJob { get; set; } = default!;

        public async Task<IActionResult> OnGetAsync(int? id)
        {
            if (id == null)
            {
                return NotFound();
            }

            var testjob =  await _context.TestJobs.FirstOrDefaultAsync(m => m.ID == id);
            if (testjob == null)
            {
                return NotFound();
            }
            TestJob = new ViewEditTestJob();
            TestJob.ID = testjob.ID;
            TestJob.WorkerStart = testjob.WorkerStart;
            TestJob.WorkerEnd = testjob.WorkerEnd;
            TestJob.Status = testjob.Status;
            TestJob.Result = testjob.Result;
            TestJob.WorkerName = testjob.WorkerName;
            TestJob.WorkerIP = testjob.WorkerIP;
            TestJob.WorkerRemoteIP = testjob.WorkerRemoteIP;
            TestJob.TestUser = testjob.TestUser;
            TestJob.TestOutput = testjob.TestOutput;
            TestJob.SchedulerLog = testjob.SchedulerLog;
            TestJob.DetectedAlerts = testjob.DetectedAlerts;
            TestJob.ReviewResult = testjob.ReviewResult;

            
            return Page();
        }

        // To protect from overposting attacks, enable the specific properties you want to bind to.
        // For more information, see https://aka.ms/RazorPagesCRUD.
        public async Task<IActionResult> OnPostAsync()
        {
            if (!ModelState.IsValid)
            {
                return Page();
            }
            if (TestJob == null)
            {
                return NotFound();
            }

            var testjob = await _context.TestJobs.Include(u => u.UseCase).FirstOrDefaultAsync(m => m.ID == TestJob.ID);
            if (testjob == null)
            {
                return NotFound();
            }
            testjob.WorkerStart = TestJob.WorkerStart;
            testjob.WorkerEnd = TestJob.WorkerEnd;
            testjob.Status = TestJob.Status;
            testjob.Result = TestJob.Result;
            testjob.WorkerName = TestJob.WorkerName;
            testjob.WorkerIP = TestJob.WorkerIP;
            testjob.WorkerRemoteIP = TestJob.WorkerRemoteIP;
            testjob.TestUser = TestJob.TestUser;
            testjob.TestOutput = TestJob.TestOutput;
            testjob.SchedulerLog = TestJob.SchedulerLog;
            testjob.DetectedAlerts = TestJob.DetectedAlerts;
            testjob.ReviewResult = TestJob.ReviewResult;

            try
            {
                await _context.SaveChangesAsync();
            }
            catch (DbUpdateConcurrencyException)
            {
                if (!TestJobExists(TestJob.ID))
                {
                    return NotFound();
                }
                else
                {
                    throw;
                }
            }

            return RedirectToPage("./Index");
        }

        private bool TestJobExists(int id)
        {
            return _context.TestJobs.Any(e => e.ID == id);
        }
    }
}
