using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.EntityFrameworkCore;
using ShieldChecker.WebApp;
using ShieldChecker.WebApp.Models.Db;

namespace ShieldChecker.WebApp.Pages.Tests
{
    public class TestExtended : TestDefinition
    {
        public Guid ModifiedById { get; set; }
    }
    public class HistoryModel : PageModel
    {
        private readonly ShieldChecker.WebApp.ShieldCheckerContext _context;

        public HistoryModel(ShieldChecker.WebApp.ShieldCheckerContext context)
        {
            _context = context;
        }

        public IList<TestExtended> Test { get; set; } = default!;

        public async Task<IActionResult> OnPostRestore(int? id, DateTime? datetime)
        {
            if (id == null || datetime == null)
            {
                return NotFound();
            }

            var test = await _context.UseCaseTests.FindAsync(id);
            if (test == null)
            {
                return NotFound();
            }
            IList<UserInfo> users = await _context.UserInfo.ToListAsync();
            Test = await _context.UseCaseTests.TemporalAll<TestDefinition>()
                .Where(t => t.ID == id)
                .Select(t => new TestExtended
                {
                    ID = t.ID,
                    Name = t.Name,
                    Description = t.Description,
                    ScriptTest = t.ScriptTest,
                    ExpectedAlertTitle = t.ExpectedAlertTitle,
                    Modified = t.Modified,
                    Enabled = t.Enabled,
                    OperatingSystem = t.OperatingSystem,
                    ElevationRequired = t.ElevationRequired,
                    ReadOnly = t.ReadOnly,
                    MitreTechnique = t.MitreTechnique,
                    ModifiedById = EF.Property<Guid>(t, "ModifiedById")
                })
                .ToListAsync();
            Test = Test.Where(t =>
                t.Modified.Year == datetime.Value.Year &&
                t.Modified.Month == datetime.Value.Month &&
                t.Modified.Day == datetime.Value.Day &&
                t.Modified.Hour == datetime.Value.Hour &&
                t.Modified.Minute == datetime.Value.Minute &&
                t.Modified.Second == datetime.Value.Second
                ).ToList();
            test.ScriptTest = Test[0].ScriptTest;
            test.ExpectedAlertTitle = Test[0].ExpectedAlertTitle;
            test.ScriptPrerequisites = Test[0].ScriptPrerequisites;
            test.ScriptCleanup = Test[0].ScriptCleanup;
            test.ExecutorSystemType = Test[0].ExecutorSystemType;
            test.ExecutorUserType = Test[0].ExecutorUserType;
            test.Description = Test[0].Description;
            test.Name = Test[0].Name;
            test.ElevationRequired = Test[0].ElevationRequired;
            test.OperatingSystem = Test[0].OperatingSystem;
            test.ReadOnly = Test[0].ReadOnly;
            test.Enabled = Test[0].Enabled;
            test.MitreTechnique = Test[0].MitreTechnique;
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
            IList<UserInfo> users = await _context.UserInfo.ToListAsync();
            Test = await _context.UseCaseTests.TemporalAll<TestDefinition>()
                .Where(t => t.ID == id).OrderByDescending(t => t.Modified)
                .Select(t => new TestExtended
                {
                    ID = t.ID,
                    Name = t.Name,
                    Enabled = t.Enabled,
                    Description = t.Description,
                    ScriptTest = t.ScriptTest,
                    ExpectedAlertTitle = t.ExpectedAlertTitle,
                    Modified = t.Modified,
                    ModifiedById = EF.Property<Guid>(t, "ModifiedById")
                })
                .ToListAsync();

            foreach (var t in Test)
            {
                t.ModifiedBy = users.FirstOrDefault(u => u.Id == t.ModifiedById);               
            }
            return Page();
        }
    }
}
