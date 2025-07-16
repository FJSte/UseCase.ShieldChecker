using System.ComponentModel.DataAnnotations;

namespace ShieldChecker.WebApp.Models.View
{
    public class ViewCreateTest
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
        [Display(Name = "Expected alert title")]
        public string ExpectedAlertTitle { get; set; } = string.Empty;

    }
}
