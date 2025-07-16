using Azure.Core;
using Azure.Identity;
using ShieldChecker.WebApp.Models.View;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;
using Microsoft.EntityFrameworkCore;
using Microsoft.Identity.Client.Platforms.Features.DesktopOs.Kerberos;
using System.IdentityModel.Tokens.Jwt;

namespace ShieldChecker.WebApp.Pages.FirstRun
{
    public class Step2 : PageModel
    {
        private readonly ILogger<IndexModel> _logger;
        private readonly ShieldCheckerContext _context;
        private readonly IHostEnvironment _hostEnvironment;
        private readonly List<string> requiredGraphScopes;
        private readonly List<string> requiredMsMdeScopes;

        public Step2(ILogger<IndexModel> logger, ShieldCheckerContext context,IHostEnvironment hostEnvironment)
        {
            _logger = logger;
            _context = context;
            _hostEnvironment = hostEnvironment;
            requiredGraphScopes = new List<string> { "SecurityAlert.ReadWrite.All" };
            requiredMsMdeScopes = new List<string> { "Machine.ReadWrite.All",  "Machine.Offboard" };
        }
        [BindProperty]
        public ViewFirstRunStep2 FirstRun { get; set; } = default!;



        public async Task<IActionResult> OnGetAsync()
        {
            FirstRun = new ViewFirstRunStep2();
            
            if (!_hostEnvironment.IsDevelopment())
            {
                
                try
                {
                    var d = new DefaultAzureCredential();
                    var graphScopes = GetScopesFromCredentials(d, "https://graph.microsoft.com");
                    FirstRun.MsGraphScopes = graphScopes;
                    FirstRun.IsMsGraphOK = graphScopes.Intersect(requiredGraphScopes).Count() == requiredGraphScopes.Count;
                    // Debug
                    var t =d.GetToken(new Azure.Core.TokenRequestContext(new string[] { "https://graph.microsoft.com" }));
                    var handler = new JwtSecurityTokenHandler();
                    var TokenDecoded = handler.ReadJwtToken(t.Token);
                    FirstRun.MsGraphScopes.Add("Payload: " + TokenDecoded.RawPayload);
                    FirstRun.MsGraphScopes.Add("Header: " + TokenDecoded.RawHeader);
                    FirstRun.MsGraphScopes.Add("Token: " + t.Token);

                } catch (Exception e)
                {
                    FirstRun.MsGraphScopes = [e.Message];
                    if(e.StackTrace != null)
                        FirstRun.MsGraphScopes.Add(e.StackTrace);
                    FirstRun.IsMsGraphOK = false;
                }
                FirstRun.RequiredMsGraphScopes = requiredGraphScopes;
                try
                {
                    var d = new DefaultAzureCredential();
                    var mdeScopes = GetScopesFromCredentials(d, "https://api.securitycenter.microsoft.com");
                    FirstRun.MsMdeScopes = mdeScopes;
                    FirstRun.IsMsMdeOK = mdeScopes.Intersect(requiredMsMdeScopes).Count() == requiredMsMdeScopes.Count;
                    FirstRun.RemediationScript = "# Manual assign Azure Custom RBAC Role to App Service Principle\r\n$managedIdentityId = '" + GetOid(d, "https://graph.microsoft.com") + "'\r\n$myPermissions = \"Machine.Offboard\", \"Machine.ReadWrite.All\"\r\n$myGPermissions = \"SecurityAlert.ReadWrite.All\"\r\n\r\nConnect-MgGraph -Scopes 'Application.ReadWrite.All,AppRoleAssignment.ReadWrite.All'\r\n\r\n$msi = Get-MgServicePrincipal -Filter \"Id eq '$managedIdentityId'\"\r\n\r\n$mde = Get-MgServicePrincipal -Filter \"AppId eq 'fc780465-2017-40d4-a0c5-307022471b92'\"\r\n\r\nforeach ($myPerm in $myPermissions) {\r\n  $permission = $mde.AppRoles `\r\n      | Where-Object Value -Like $myPerm `\r\n      | Select-Object -First 1\r\n\r\n  if ($permission) {\r\n    New-MgServicePrincipalAppRoleAssignment `\r\n        -ServicePrincipalId $msi.Id `\r\n        -AppRoleId $permission.Id `\r\n        -PrincipalId $msi.Id `\r\n        -ResourceId $mde.Id\r\n  }\r\n}\r\n\r\n$graph = Get-MgServicePrincipal -Filter \"AppId eq '00000003-0000-0000-c000-000000000000'\"\r\n\r\nforeach ($myPerm in $myGPermissions) {\r\n  $permission = $graph.AppRoles `\r\n      | Where-Object Value -Like $myPerm `\r\n      | Select-Object -First 1\r\n\r\n  if ($permission) {\r\n    New-MgServicePrincipalAppRoleAssignment `\r\n        -ServicePrincipalId $msi.Id `\r\n        -AppRoleId $permission.Id `\r\n        -PrincipalId $msi.Id `\r\n        -ResourceId $graph.Id\r\n  }\r\n}";

                }
                catch (Exception e)
                {
                    FirstRun.MsMdeScopes = [$"Error: {e.Message}"];
                    if (e.StackTrace != null)
                        FirstRun.MsMdeScopes.Add(e.StackTrace);
                    FirstRun.IsMsMdeOK = false;
                }
                FirstRun.RequiredMsMdeScopes = requiredMsMdeScopes;
                
            }
            else
            {
                FirstRun.MsGraphScopes = new List<string>();
                FirstRun.RequiredMsGraphScopes = requiredGraphScopes;
                FirstRun.IsMsGraphOK = true;
                FirstRun.MsMdeScopes = new List<string>();
                FirstRun.RequiredMsMdeScopes = requiredMsMdeScopes;
                FirstRun.IsMsMdeOK = true;
                FirstRun.RemediationScript = "# Manual assign Azure Custom RBAC Role to App Service Principle\r\n$managedIdentityId = 'YOURAPPID'\r\n$myPermissions = \"Machine.Offboard\", \"Machine.ReadWrite.All\"\r\n$myGPermissions = \"SecurityAlert.ReadWrite.All\"\r\n\r\nConnect-MgGraph -Scopes 'Application.ReadWrite.All,AppRoleAssignment.ReadWrite.All'\r\n\r\n$msi = Get-MgServicePrincipal -Filter \"Id eq '$managedIdentityId'\"\r\n\r\n$mde = Get-MgServicePrincipal -Filter \"AppId eq 'fc780465-2017-40d4-a0c5-307022471b92'\"\r\n\r\nforeach ($myPerm in $myPermissions) {\r\n  $permission = $mde.AppRoles `\r\n      | Where-Object Value -Like $myPerm `\r\n      | Select-Object -First 1\r\n\r\n  if ($permission) {\r\n    New-MgServicePrincipalAppRoleAssignment `\r\n        -ServicePrincipalId $msi.Id `\r\n        -AppRoleId $permission.Id `\r\n        -PrincipalId $msi.Id `\r\n        -ResourceId $mde.Id\r\n  }\r\n}\r\n\r\n$graph = Get-MgServicePrincipal -Filter \"AppId eq '00000003-0000-0000-c000-000000000000'\"\r\n\r\nforeach ($myPerm in $myGPermissions) {\r\n  $permission = $graph.AppRoles `\r\n      | Where-Object Value -Like $myPerm `\r\n      | Select-Object -First 1\r\n\r\n  if ($permission) {\r\n    New-MgServicePrincipalAppRoleAssignment `\r\n        -ServicePrincipalId $msi.Id `\r\n        -AppRoleId $permission.Id `\r\n        -PrincipalId $msi.Id `\r\n        -ResourceId $graph.Id\r\n  }\r\n}";

            }


            return Page();
        }

        private List<string> GetScopesFromCredentials(DefaultAzureCredential Credential, string RessourceUrl)
        {
            var t = Credential.GetToken(new Azure.Core.TokenRequestContext(new string[] { RessourceUrl }));
            var handler = new JwtSecurityTokenHandler();
            var TokenDecoded = handler.ReadJwtToken(t.Token);
            
            return TokenDecoded.Claims.Where(c => c.Type == "roles").Select(c => c.Value).ToList();
        }

        private string GetOid(DefaultAzureCredential Credential, string RessourceUrl)
        {
            var t = Credential.GetToken(new Azure.Core.TokenRequestContext(new string[] { RessourceUrl }));
            var handler = new JwtSecurityTokenHandler();
            var TokenDecoded = handler.ReadJwtToken(t.Token);
            return TokenDecoded.Claims.Where(c => c.Type == "oid").First().Value;
        }

    }
}
