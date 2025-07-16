using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.AspNetCore.Mvc.Rendering;
using ShieldChecker.WebApp;
using ShieldChecker.WebApp.Models.Db;

namespace ShieldChecker.WebApp.Pages.Settings.AutoScheduler
{
    public class CreateModel : TestDefinitionSelectorPageModel
    {
        private readonly ShieldChecker.WebApp.ShieldCheckerContext _context;

        public CreateModel(ShieldChecker.WebApp.ShieldCheckerContext context)
        {
            _context = context;
        }

        public IActionResult OnGet()
        {

            PopulateTestDefinitionsDropDownList(_context,new List<TestDefinition>());

            return Page();
        }

        [BindProperty]
        public AutoSchedule AutoSchedule { get; set; } = default!;

        // For more information, see https://aka.ms/RazorPagesCRUD.
        public async Task<IActionResult> OnPostAsync()
        {
            if (!ModelState.IsValid)
            {
                return Page();
            } 
            if (this.Request.Form["AutoSchedule.TestDefinitions"].Count > 0) {
                List<string> sel = this.Request.Form["AutoSchedule.TestDefinitions"].ToList<string>();
   
                AutoSchedule.TestDefinitions = _context.UseCaseTests.Where(c => sel.Contains(c.ID.ToString())).ToList();
            }


            _context.AutoSchedule.Add(AutoSchedule);
            await _context.SaveChangesAsync();

            return RedirectToPage("./Index");
        }
    }
}
