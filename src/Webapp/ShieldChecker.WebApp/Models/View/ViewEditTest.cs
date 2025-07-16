using System.ComponentModel.DataAnnotations;

namespace ShieldChecker.WebApp.Models.View
{
    public class ViewEditTest
    {
        public int ID { get; set; }
        [Required]
        [StringLength(150)]
        [Display(Name = "Name")]
        public string Name { get; set; } = string.Empty;
        [StringLength(16)]
        public string MitreTechnique { get; set; } = string.Empty;
        public string Description { get; set; } = string.Empty;

        [Required]
        [StringLength(256)]
        [Display(Name = "Expected alert title (Comma seperated if multiple)")]
        public string ExpectedAlertTitle { get; set; } = string.Empty;

        [Required]
        [Display(Name = "Main Test Script")]
        public string ScriptTest { get; set; } = string.Empty;
        [Display(Name = "Prerequisites Script")]
        public string ScriptPrerequisites { get; set; } = string.Empty;
        [Display(Name = "Cleanup Script")]
        public string ScriptCleanup { get; set; } = string.Empty;

        public ShieldChecker.WebApp.Models.Db.OperatingSystem OperatingSystem { get; set; }
        public ShieldChecker.WebApp.Models.Db.ExecutorSystemType ExecutorSystemType { get; set; }
        public ShieldChecker.WebApp.Models.Db.ExecutorUserType ExecutorUserType { get; set; }

        public bool ElevationRequired { get; set; }
        public bool Enabled { get; set; }

    }
}
