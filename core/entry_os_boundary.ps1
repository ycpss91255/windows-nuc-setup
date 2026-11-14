#Requires -Version 5.1
function Get-SetupEntryIdentity { [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
function Test-SetupEntryAdministrator {
 $principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
 return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
