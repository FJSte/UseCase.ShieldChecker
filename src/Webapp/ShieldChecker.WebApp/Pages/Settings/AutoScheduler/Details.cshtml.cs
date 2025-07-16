using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.EntityFrameworkCore;
using ShieldChecker.WebApp;
using ShieldChecker.WebApp.Models.Db;

namespace ShieldChecker.WebApp.Pages.Settings.AutoScheduler
{
    public class DetailsModel : PageModel
    {
        private readonly ShieldChecker.WebApp.ShieldCheckerContext _context;

        public DetailsModel(ShieldChecker.WebApp.ShieldCheckerContext context)
        {
            _context = context;
        }

        public AutoSchedule AutoSchedule { get; set; } = default!;

        public async Task<IActionResult> OnGetAsync(int? id)
        {
            if (id == null)
            {
                return NotFound();
            }

            var autoschedule = await _context.AutoSchedule.FirstOrDefaultAsync(m => m.ID == id);

            if (autoschedule is not null)
            {
                AutoSchedule = autoschedule;

                return Page();
            }

            return NotFound();
        }
    }
}
