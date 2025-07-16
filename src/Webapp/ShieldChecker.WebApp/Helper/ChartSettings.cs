namespace ShieldChecker.WebApp.Helper
{
    public static class ChartSettings
    {
        public static List<string> ChartColors { 
            get {
                return new List<string>()
                    {
                        "rgb(59, 125, 221)",
                        "rgb(10, 10, 10)",
                        "rgb(111, 66, 193)",
                        "rgb(232, 62, 140)",
                        "rgb(220, 53, 69)",
                        "rgb(253, 126, 20)",
                        "rgb(252, 185, 44)",
                        "rgb(28, 187, 140)",
                        "rgb(32, 201, 151)",
                        "rgb(23, 162, 184)"
                    };
                }  
        }
        public static List<string> ChartColorPrimary
        {
            get
            {
                return new List<string>()
                    {
                        "rgb(59, 125, 221)"
                    };
            }
        }
        public static List<string> ChartColorSecondary
        {
            get
            {
                return new List<string>()
                    {
                        "rgb(10, 10, 10)"
                    };
            }
        }
    }
}
