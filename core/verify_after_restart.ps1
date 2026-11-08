#Requires -Version 5.1
param([string]$ExpectedUserSID)
$ErrorActionPreference='Stop'
$currentSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($ExpectedUserSID -and $ExpectedUserSID -ne $currentSID){throw '提權後帳號已改變，請使用原帳號的管理員權限。'}
. (Join-Path $PSScriptRoot 'paths.ps1')
Initialize-NucReports
$DriverPackagePath=Get-SetupSavedDriverSelection -ResultPath (Resolve-NucPath 'Setup-Result.json')
$confirmation=Get-SetupSavedHardwareConfirmation -ResultPath (Resolve-NucPath 'Setup-Result.json')
$hardware=Get-SetupHardwareProfile -DriverPackagePath $DriverPackagePath @confirmation
$skippedModules=@(@('install_drivers.ps1','apply_amd_privacy_settings.ps1','desktop_icon_layout.ps1')|ForEach-Object {Get-SetupModuleDecision -Module $_ -Hardware $hardware}|Where-Object {-not $_.Applicable})
$p=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
 $command="& '"+$PSCommandPath.Replace("'","''")+"' -ExpectedUserSID '"+$currentSID+"'"
 Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)));exit
}
& (Resolve-NucPath 'test_setup_prerequisites.ps1') -DriverPackagePath $DriverPackagePath @confirmation
if($hardware.IsNuc8 -and $DriverPackagePath){$hardware|Add-Member -NotePropertyName DriverSelection -NotePropertyValue (New-SetupDriverSelection -PackageRoot $script:NucPackageRoot -DriverPackagePath $DriverPackagePath) -Force}
. (Resolve-NucPath 'after_restart_library.ps1')
Invoke-SetupAfterRestart -Hardware $hardware -DriverPackagePath $DriverPackagePath -Confirmation $confirmation -SkippedModules $skippedModules
