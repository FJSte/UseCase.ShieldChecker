# Define App UAMI Permissions
$AppManagedIdentityId = '1573c44d-67c6-406d-9394-046b3da47a70' # Object ID


# Define DB UAMI Permissions
$DbManagedIdentityId = '1573c44d-67c6-406d-9394-046b3da47a70' # Object ID


# Define Permissions
$AppSecGraphPermissions = "Machine.Offboard", "Machine.ReadWrite.All"
$AppGraphPermissions = "SecurityAlert.ReadWrite.All"
$DbGraphPermissions = "SecurityAlert.ReadWrite.All"

Connect-MgGraph -Scopes 'Application.ReadWrite.All,AppRoleAssignment.ReadWrite.All'

$AppMsi = Get-MgServicePrincipal -Filter "Id eq '$AppManagedIdentityId'"
$DbMsi = Get-MgServicePrincipal -Filter "Id eq '$DbManagedIdentityId'"

$mde = Get-MgServicePrincipal -Filter "AppId eq 'fc780465-2017-40d4-a0c5-307022471b92'"

foreach ($myPerm in $AppSecGraphPermissions) {
  $permission = $mde.AppRoles `
      | Where-Object Value -Like $myPerm `
      | Select-Object -First 1

  if ($permission) {
    Write-Host "Assign MS Security Graph $myPerm to $($AppMsi.DisplayName)"
    New-MgServicePrincipalAppRoleAssignment `
        -ServicePrincipalId $AppMsi.Id `
        -AppRoleId $permission.Id `
        -PrincipalId $AppMsi.Id `
        -ResourceId $mde.Id
  }
}

$graph = Get-MgServicePrincipal -Filter "AppId eq '00000003-0000-0000-c000-000000000000'"

foreach ($myPerm in $AppGraphPermissions) {
  $permission = $graph.AppRoles `
      | Where-Object Value -Like $myPerm `
      | Select-Object -First 1

  if ($permission) {
    Write-Host "Assign MS Graph $myPerm to $($AppMsi.DisplayName)"
    New-MgServicePrincipalAppRoleAssignment `
        -ServicePrincipalId $AppMsi.Id `
        -AppRoleId $permission.Id `
        -PrincipalId $AppMsi.Id `
        -ResourceId $graph.Id
  }
}

foreach ($myPerm in $AppGraphPermissions) {
  $permission = $graph.AppRoles `
      | Where-Object Value -Like $myPerm `
      | Select-Object -First 1

  if ($permission) {
    Write-Host "Assign MS Graph $myPerm to $($DbMsi.DisplayName)"
    New-MgServicePrincipalAppRoleAssignment `
        -ServicePrincipalId $DbMsi.Id `
        -AppRoleId $permission.Id `
        -PrincipalId $DbMsi.Id `
        -ResourceId $graph.Id
  }
}