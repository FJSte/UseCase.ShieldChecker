﻿using System;
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
using Microsoft.EntityFrameworkCore.Metadata.Internal;
using Azure;
using Microsoft.AspNetCore.Builder.Extensions;


namespace ShieldChecker.WebApp.Pages.Tests
{
    public class EditModel : PageModel
    {
        private readonly ShieldChecker.WebApp.ShieldCheckerContext _context;

        public EditModel(ShieldChecker.WebApp.ShieldCheckerContext context)
        {
            _context = context;
        }

        [BindProperty]
        public ViewEditTest Test { get; set; } = default!;
        public async Task<IActionResult> OnGetAsync(int? id)
        {
            if (id == null)
            {
                return NotFound();
            }

            var test = await _context.UseCaseTests.FindAsync(id);
            if (test == null)
            {
                return NotFound();
            }
            if (test.ReadOnly.HasValue && test.ReadOnly.Value)
            {
                return RedirectToPage("./Details", new { id = test.ID });
            }


            Test = new ViewEditTest();
            Test.ID = test.ID;
            Test.ScriptPrerequisites = test.ScriptPrerequisites;
            Test.ScriptTest = test.ScriptTest;
            Test.ScriptCleanup = test.ScriptCleanup;
            Test.Name = test.Name;
            Test.Description = test.Description;
            Test.ExpectedAlertTitle = test.ExpectedAlertTitle;
            Test.ElevationRequired = test.ElevationRequired;
            Test.OperatingSystem = test.OperatingSystem;
            Test.MitreTechnique = test.MitreTechnique;
            Test.ExecutorSystemType = test.ExecutorSystemType;
            Test.ExecutorUserType = test.ExecutorUserType;
            if (!test.Enabled.HasValue)
            {
                Test.Enabled = false;
            }
            else
            {
                Test.Enabled = test.Enabled.Value;
            }

            return Page();
        }

        // To protect from overposting attacks, enable the specific properties you want to bind to.
        // For more information, see https://aka.ms/RazorPagesCRUD.
        public async Task<IActionResult> OnPostAsync(int? id, IFormCollection Form)
        {
            if (!ModelState.IsValid)
            {
                return Page();
            }
            var test = await _context.UseCaseTests.FindAsync(id);
            if (test == null)
            {
                return NotFound();
            }
            if (test.ReadOnly.HasValue && test.ReadOnly.Value)
            {
                return RedirectToPage("./Details", new { id = test.ID });
            }

            test.Name = Test.Name;
            test.Description = Test.Description;
            test.ScriptCleanup = Test.ScriptCleanup;
            test.ScriptPrerequisites = Test.ScriptPrerequisites;
            test.ScriptTest = Test.ScriptTest;
            test.ExpectedAlertTitle = Test.ExpectedAlertTitle;
            test.ElevationRequired = Test.ElevationRequired;
            test.MitreTechnique = Test.MitreTechnique;
            test.ExecutorSystemType = Test.ExecutorSystemType;
            test.ExecutorUserType = Test.ExecutorUserType;
            test.OperatingSystem = Test.OperatingSystem;

            test.Enabled = Test.Enabled;
            test.Modified = DateTime.UtcNow;
            test.ModifiedBy = UserInfo.EnsureUserInDb(User, _context);
            try
            {
                await _context.SaveChangesAsync();
                return RedirectToPage("./Index");
            }
            catch
            {
                return Page();
            }
        }

        private bool TestExists(int id)
        {
            return _context.UseCaseTests.Any(e => e.ID == id);
        }
    }
}
