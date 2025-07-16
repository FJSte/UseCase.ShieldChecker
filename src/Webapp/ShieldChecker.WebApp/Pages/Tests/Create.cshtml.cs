using System.Security.Principal;

using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.AspNetCore.Mvc.Rendering;
using ShieldChecker.WebApp;
using Microsoft.AspNetCore.Identity;

using ShieldChecker.WebApp.Models.Db;
using ShieldChecker.WebApp.Models.View;


namespace ShieldChecker.WebApp.Pages.Tests
{
    public class CreateModel : PageModel
    {
        private readonly ShieldChecker.WebApp.ShieldCheckerContext _context;

        public CreateModel(ShieldChecker.WebApp.ShieldCheckerContext context)
        {
            _context = context;
        }

        public IActionResult OnGet()
        {
            
            return Page();
        }

        [BindProperty]
        public ViewCreateTest TestVm { get; set; } = default!;

        // For more information, see https://aka.ms/RazorPagesCRUD.
        public async Task<IActionResult> OnPostAsync()
        {
            if (!ModelState.IsValid)
            {
                return Page();
            }
            UserInfo userInfo = UserInfo.EnsureUserInDb(User, _context);

            var Test = _context.Add(new ShieldChecker.WebApp.Models.Db.TestDefinition());
            Test.CurrentValues.SetValues(TestVm);
            Test.Entity.Created = DateTime.UtcNow;
            Test.Entity.Modified = DateTime.UtcNow;
            Test.Entity.ScriptTest = "";
            Test.Entity.ScriptCleanup = "";
            Test.Entity.ScriptPrerequisites = "";
            Test.Entity.OperatingSystem = Models.Db.OperatingSystem.Windows;
            Test.Entity.ExecutorSystemType = ExecutorSystemType.Worker;
            Test.Entity.ExecutorUserType = ExecutorUserType.System;
            Test.Entity.ElevationRequired = false;
            Test.Entity.Enabled = false;
            Test.Entity.ReadOnly = false;
            Test.Entity.CreatedBy = userInfo;
            Test.Entity.ModifiedBy = userInfo;
            await _context.SaveChangesAsync();
            

            return RedirectToPage("./Edit", new { id = Test.Entity.ID });
        }
    }
}
