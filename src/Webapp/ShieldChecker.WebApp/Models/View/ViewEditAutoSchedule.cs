using ShieldChecker.WebApp.Models.Db;
using System.ComponentModel.DataAnnotations;

namespace ShieldChecker.WebApp.Models.View
{
    public class ViewEditAutoSchedule
    {
        public int ID { get; set; }
        public required string Name { get; set; }
        public bool Enabled { get; set; }
        [Display(Name = "Next Execution")]
        public DateTime NextExecution { get; set; }
        [Display(Name = "AutoSchedule Type")]
        public AutoScheduleType Type { get; set; }
        [Display(Name = "Max number of Tests to select out of the filtered or selected tests per run")]
        public int? FilterRandomCount { get; set; } = 0;
        [Display(Name = "Filter by Operating System")]
        public ShieldChecker.WebApp.Models.Db.OperatingSystem? FilterOperatingSystem { get; set; }
        [Display(Name = "Filter based on past Executionresults")]
        public FilterExecution? FilterExecution { get; set; }

    }
}
