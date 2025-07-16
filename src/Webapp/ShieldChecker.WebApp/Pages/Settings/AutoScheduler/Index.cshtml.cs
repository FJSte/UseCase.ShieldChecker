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
    public class IndexModel : PageModel
    {
        private readonly ShieldChecker.WebApp.ShieldCheckerContext _context;

        public IndexModel(ShieldChecker.WebApp.ShieldCheckerContext context)
        {
            _context = context;
        }

        public IList<AutoSchedule> AutoSchedule { get;set; } = default!;

        public async Task OnGetAsync()
        {
            AutoSchedule = await _context.AutoSchedule.ToListAsync();
        }
    }
}
