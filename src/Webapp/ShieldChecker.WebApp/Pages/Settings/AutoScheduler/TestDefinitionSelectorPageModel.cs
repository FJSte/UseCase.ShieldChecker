using ShieldChecker.WebApp.Models.Db;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.AspNetCore.Mvc.Rendering;
using Microsoft.EntityFrameworkCore;

namespace ShieldChecker.WebApp.Pages.Settings.AutoScheduler
{
    public class TestDefinitionSelectorPageModel : PageModel
    {
        public List<SelectListItem> TestDefinitionOptions { get; set; } = new List<SelectListItem>();

        

        public void PopulateTestDefinitionsDropDownList(ShieldChecker.WebApp.ShieldCheckerContext _context,
            List<TestDefinition> selectedTestDefinitions)
        {
            TestDefinitionOptions  = _context.UseCaseTests.AsNoTracking().Select(a =>
                                  new SelectListItem
                                  {
                                      Value = a.ID.ToString(),
                                      Text = a.Name,
                                  }).ToList();
            foreach (var TestDefinitionOption in TestDefinitionOptions)
            {

                if (selectedTestDefinitions.Exists(x => x.ID.ToString() == TestDefinitionOption.Value))
                {
                    TestDefinitionOption.Selected = true;
                }
            }


        }
    }
}
