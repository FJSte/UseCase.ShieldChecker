using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.EntityFrameworkCore;

namespace ShieldChecker.WebApp.Pages.FirstRun
{
    public class Step3Model : PageModel
    {
        private readonly ILogger<IndexModel> _logger;
        private readonly ShieldCheckerContext _context;

        public Step3Model(ILogger<IndexModel> logger, ShieldCheckerContext context)
        {
            _logger = logger;
            _context = context;
        }

        public void OnGet()
        {
        }
        public async Task<IActionResult> OnPostAsync()
        {
            

            var systemStatus = await _context.SystemStatus.FirstOrDefaultAsync(m => m.ID == 1);
            if (systemStatus == null)
            {
                return NotFound();
            }
            systemStatus.IsFirstRunCompleted = true;

            try
            {
                await _context.SaveChangesAsync();
            }
            catch (DbUpdateConcurrencyException)
            {

                throw;

            }

            return RedirectToPage("/Index");
        }
    }
}
