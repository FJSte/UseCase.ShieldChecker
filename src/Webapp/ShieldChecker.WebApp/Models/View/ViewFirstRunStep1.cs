using System.ComponentModel.DataAnnotations;

namespace ShieldChecker.WebApp.Models.View
{
    public class ViewFirstRunStep1
    {

        [Display(Name = "Defender for Endpoint Onboarding Script for Windows")]
        [StringLength(30000, MinimumLength = 200)]
        public string MDEWindowsOnboardingScript { get; set; } = string.Empty;
        [Display(Name = "Defender for Endpoint Onboarding Script for Linux")]
        [StringLength(30000, MinimumLength = 200)]
        public string MDELinuxOnboardingScript { get; set; } = string.Empty;
    }
}
