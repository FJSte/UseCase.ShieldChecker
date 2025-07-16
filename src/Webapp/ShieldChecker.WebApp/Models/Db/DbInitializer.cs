using Microsoft.EntityFrameworkCore;
using System.Reflection;

namespace ShieldChecker.WebApp.Models.Db
{
    public static class DbInitializer
    {
        public static void Initialize(ShieldCheckerContext context,IHostEnvironment hostEnvironment)
        {
            if (hostEnvironment.IsDevelopment()) {
                // Read data from sql-initialization.sql file
                string sql = System.IO.File.ReadAllText("Models\\Db\\sql-initialization.sql");
                sql = sql.Replace("_DomainFQDN_","shieldchecker.local");
                // Seed Data

                context.Database.ExecuteSqlRaw(sql);
                var status = context.SystemStatus.Where(s => s.ID == 1).FirstOrDefault();
                status.IsFirstRunCompleted = true;
                context.SystemStatus.Update(status);
                var t = context.SaveChangesAsync();
                t.Wait();
            }
            
            if (context.SystemStatus.Count() != 1)
            {
                throw new Exception("DBNotInitialized: SystemStatus not found");

            }
            if (context.Settings.Count() != 1)
            {
                throw new Exception("DBNotInitialized: Settings not found");

            }
            if (context.UserInfo.Where(u => u.Id == new Guid("00000000-0000-0000-0000-000000000000")).Count() == 0)
            {
                throw new Exception("DBNotInitialized: System UserInfo not found");
            }


        }
    }
}
