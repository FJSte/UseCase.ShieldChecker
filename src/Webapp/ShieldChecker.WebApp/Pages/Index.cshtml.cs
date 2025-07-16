using ShieldChecker.WebApp.Models.Db;
using ShieldChecker.WebApp.Models.View;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace ShieldChecker.WebApp.Pages
{
    public class IndexModel : PageModel
    {
        private readonly ShieldChecker.WebApp.ShieldCheckerContext _context;
        private readonly ILogger<IndexModel> _logger;

        public ViewHomepageModel HomepageModel { get; set; } = default!;

        public IndexModel(ILogger<IndexModel> logger, ShieldCheckerContext context)
        {
            _logger = logger;
            _context = context;
            HomepageModel = new ViewHomepageModel();
        }

        public async Task<IActionResult> OnGetAsync()
        {
            var Status = _context.SystemStatus.Where(s => s.ID == 1).First();
            if (Status.IsFirstRunCompleted == false)
            {
                return RedirectToPage("./FirstRun/Welcome");
            }

            HomepageModel.Status = Status;

            return Page();
        }
    }
}
