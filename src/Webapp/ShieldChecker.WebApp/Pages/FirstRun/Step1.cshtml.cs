using Azure.Identity;
using ShieldChecker.WebApp.Models.View;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.EntityFrameworkCore;

namespace ShieldChecker.WebApp.Pages.FirstRun
{
    public class Step1 : PageModel
    {
        private readonly ILogger<IndexModel> _logger;
        private readonly ShieldCheckerContext _context;

        public Step1(ILogger<IndexModel> logger, ShieldCheckerContext context)
        {
            _logger = logger;
            _context = context;
        }
        [BindProperty]
        public ViewFirstRunStep1 FirstRun { get; set; } = default!;
        public async Task<IActionResult> OnGetAsync()
        {

            var settings = await _context.Settings.FirstOrDefaultAsync(m => m.ID == 1);
            if (settings == null)
            {
                return NotFound();
            }
            FirstRun = new ViewFirstRunStep1
            {
                MDEWindowsOnboardingScript = settings.MDEWindowsOnboardingScript,
                MDELinuxOnboardingScript = settings.MDELinuxOnboardingScript
            };
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

            var settings = await _context.Settings.FirstOrDefaultAsync(m => m.ID == 1);
            if (settings == null)
            {
                return NotFound();
            }
            settings.MDEWindowsOnboardingScript = FirstRun.MDEWindowsOnboardingScript;
            settings.MDELinuxOnboardingScript = FirstRun.MDELinuxOnboardingScript;

            try
            {
                await _context.SaveChangesAsync();
            }
            catch (DbUpdateConcurrencyException)
            {

                throw;

            }

            return RedirectToPage("/FirstRun/Step2");
        }

    }
}
