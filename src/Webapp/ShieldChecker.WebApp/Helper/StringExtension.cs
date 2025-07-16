using System.Text.RegularExpressions;

namespace ShieldChecker.WebApp.Helper
{

    public static class StringExtension
    {
        public static string ToStringOrEmpty(this object value)
        {
            return string.Concat(value, "");
        }

        /// <summary>
        /// Converts a string from CamelCase to a human readable format. 
        /// Inserts spaces between upper and lower case letters. 
        /// Also strips the leading "_" character, if it exists.
        /// </summary>
        /// <param name="propertyName"></param>
        /// <returns>A human readable string.</returns>
        public static string FromCamelCase(this string propertyName)
        {
            string returnValue = null;
            returnValue = propertyName.ToStringOrEmpty();

            //Strip leading "_" character
            returnValue = Regex.Replace(returnValue, "^_", "").Trim();
            //Add a space between each lower case character and upper case character
            returnValue = Regex.Replace(returnValue, "([a-z])([A-Z])", "$1 $2").Trim();
            //Add a space between 2 upper case characters when the second one is followed by a lower space character
            returnValue = Regex.Replace(returnValue, "([A-Z])([A-Z][a-z])", "$1 $2").Trim();

            return returnValue;
        }
    }

}
