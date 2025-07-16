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

namespace ShieldChecker.WebApp.Pages.Settings.AutoScheduler
{
    public class EditModel : TestDefinitionSelectorPageModel
    {
        private readonly ShieldChecker.WebApp.ShieldCheckerContext _context;

        public EditModel(ShieldChecker.WebApp.ShieldCheckerContext context)
        {
            _context = context;
        }

        [BindProperty]
        public ViewEditAutoSchedule ViewEditAutoSchedule { get; set; } = default!;

        public async Task<IActionResult> OnGetAsync(int? id)
        {
            if (id == null)
            {
                return NotFound();
            }

            AutoSchedule AutoSchedule =  await _context.AutoSchedule.Include(x => x.TestDefinitions).FirstOrDefaultAsync(m => m.ID == id);
            if (AutoSchedule == null)
            {
                return NotFound();
            }
            PopulateTestDefinitionsDropDownList(_context, AutoSchedule.TestDefinitions);
            ViewEditAutoSchedule = new ViewEditAutoSchedule() { Name = AutoSchedule.Name};
            ViewEditAutoSchedule.ID = AutoSchedule.ID;
            ViewEditAutoSchedule.Name = AutoSchedule.Name;
            ViewEditAutoSchedule.NextExecution = AutoSchedule.NextExecution;
            ViewEditAutoSchedule.Enabled = AutoSchedule.Enabled;
            ViewEditAutoSchedule.Type = AutoSchedule.Type;
            ViewEditAutoSchedule.FilterRandomCount = AutoSchedule.FilterRandomCount;
            ViewEditAutoSchedule.FilterOperatingSystem = AutoSchedule.FilterOperatingSystem;
            ViewEditAutoSchedule.FilterExecution = AutoSchedule.FilterExecution;


            return Page();
        }

        // To protect from overposting attacks, enable the specific properties you want to bind to.
        // For more information, see https://aka.ms/RazorPagesCRUD.
        public async Task<IActionResult> OnPostAsync(int? id)
        {
            if (id == null && id == ViewEditAutoSchedule.ID)
            {
                return NotFound();
            }

            if (!ModelState.IsValid)
            {
                return Page();
            }
            AutoSchedule AutoScheduleNew = await _context.AutoSchedule.Include(x => x.TestDefinitions).FirstOrDefaultAsync(m => m.ID == id);
            if (AutoScheduleNew == null)
            {
                return NotFound();
            }
            AutoScheduleNew.Enabled = ViewEditAutoSchedule.Enabled;
            AutoScheduleNew.Name = ViewEditAutoSchedule.Name;
            AutoScheduleNew.NextExecution = ViewEditAutoSchedule.NextExecution;
            AutoScheduleNew.Type = ViewEditAutoSchedule.Type;
            AutoScheduleNew.FilterRandomCount = ViewEditAutoSchedule.FilterRandomCount;
            AutoScheduleNew.FilterOperatingSystem = ViewEditAutoSchedule.FilterOperatingSystem;
            AutoScheduleNew.FilterExecution = ViewEditAutoSchedule.FilterExecution;


            if (this.Request.Form["SelectedTestDefinitions"].Count > 0)
            {
                
                List<string> sel = this.Request.Form["SelectedTestDefinitions"].ToList<string>();

                // Remove no longer selected items from existing List
                AutoScheduleNew.TestDefinitions.RemoveAll(x => !sel.Contains(x.ID.ToString()));

                // Add new selected elements
                List<string> AlreadySelected = AutoScheduleNew.TestDefinitions.Select(x => x.ID.ToString()).ToList();
                sel.RemoveAll(x => AlreadySelected.Exists(y => y.Equals(x)));
                AutoScheduleNew.TestDefinitions.AddRange(_context.UseCaseTests.Where(c => sel.Contains(c.ID.ToString())).ToList());
            } else
            {
                AutoScheduleNew.TestDefinitions.Clear();
            }

            try
            {
                await _context.SaveChangesAsync();
            }
            catch (DbUpdateConcurrencyException)
            {
                if (!AutoScheduleExists(ViewEditAutoSchedule.ID))
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

        private bool AutoScheduleExists(int id)
        {
            return _context.AutoSchedule.Any(e => e.ID == id);
        }
    }
}
