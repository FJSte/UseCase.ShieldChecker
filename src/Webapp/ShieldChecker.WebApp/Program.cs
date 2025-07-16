using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.OpenIdConnect;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc.Authorization;
using Microsoft.Identity.Web;
using Microsoft.Identity.Web.UI;
using Microsoft.EntityFrameworkCore;
using ShieldChecker.WebApp.Models.Db;
using Azure.Identity;
using ShieldChecker.WebApp.Services;

namespace ShieldChecker.WebApp
{
    public class Program
    {
        public static void Main(string[] args)
        {
            var builder = WebApplication.CreateBuilder(args);
            if (builder.Environment.IsProduction())
            {
                builder.Services.AddApplicationInsightsTelemetry();
            }
            // Add services to the container.
            builder.Services.AddAuthentication(OpenIdConnectDefaults.AuthenticationScheme)
                .AddMicrosoftIdentityWebApp(builder.Configuration.GetSection("AzureAd"));

            builder.Services.AddAuthorization(options =>
            {
                // By default, all incoming requests will be authorized according to the default policy.
                options.FallbackPolicy = options.DefaultPolicy;
            });
            builder.Services.AddRazorPages()
                .AddMicrosoftIdentityUI();

            builder.Services.AddDbContext<ShieldCheckerContext>(options =>
                options.UseSqlServer(builder.Configuration.GetValue<string>("AzureSqlDatabase")));
            builder.Services.AddDatabaseDeveloperPageExceptionFilter();
            if (builder.Environment.IsProduction())
            {
                
                builder.Configuration.AddAzureKeyVault(new Uri(builder.Configuration["KEYVAULT_URI"]),new DefaultAzureCredential());
            }
            builder.Services.AddServerSideBlazor();
            builder.Services.AddHttpClient();
            builder.Services.AddScoped<IAzureFunctionService, AzureFunctionService>();

            var app = builder.Build();

            // Configure the HTTP request pipeline.
            if (!app.Environment.IsDevelopment())
            {
                app.UseExceptionHandler("/Error");
                // The default HSTS value is 30 days. You may want to change this for production scenarios, see https://aka.ms/aspnetcore-hsts.
                app.UseHsts();
            }
            else
            {
                app.UseDeveloperExceptionPage();
                app.UseMigrationsEndPoint();
            }
            using (var scope = app.Services.CreateScope())
            {
                var services = scope.ServiceProvider;

                var context = services.GetRequiredService<ShieldCheckerContext>();

                DbInitializer.Initialize(context, app.Environment);

  
            }
            

            app.UseHttpsRedirection();
            app.UseStaticFiles();

            app.UseRouting();

            app.UseAuthentication();

            app.UseAuthorization();

            app.MapRazorPages();
            app.MapBlazorHub();
            app.MapControllers();

            app.Run();
        }
    }
}
