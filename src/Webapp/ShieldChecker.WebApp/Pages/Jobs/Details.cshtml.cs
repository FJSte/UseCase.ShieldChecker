using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.EntityFrameworkCore;
using ShieldChecker.WebApp;
using ShieldChecker.WebApp.Models.Db;

namespace ShieldChecker.WebApp.Pages.Jobs
{
    public class DetailsModel : PageModel
    {
        private readonly ShieldChecker.WebApp.ShieldCheckerContext _context;
        private readonly IConfiguration _config;
        private string AlertData = "";

        public DetailsModel(ShieldChecker.WebApp.ShieldCheckerContext context, IConfiguration config)
        {
            _context = context;
            _config = config;
        }

        public TestJob TestJob { get; set; } = default!;

        public async Task<IActionResult> OnGetAsync(int? id)
        {
            if (id == null)
            {
                return NotFound();
            }

            // var testjob = await _context.TestJobs.Include(u => u.UseCase).FirstOrDefaultAsync(m => m.ID == id);
            var testjob = _context.TestJobs.Include(u => u.UseCase).FirstOrDefault(m => m.ID == id);

            if (testjob is not null)
            {
                TestJob = testjob;

                return Page();
            }

            return NotFound();
        }

        
        
    }
}
