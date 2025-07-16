using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace ShieldChecker.WebApp.Pages.Settings
{
    public class DcLogModel : PageModel
    {
        private readonly ShieldCheckerContext _context;

        [BindProperty]
        public Models.Db.SystemStatus SystemStatus { get; set; } = default!;

        public DcLogModel(ShieldCheckerContext context)
        {
            _context = context;
        }


        public void OnGet()
        {
            SystemStatus = _context.SystemStatus.Where(s => s.ID == 1).First();
        }
    }
}
