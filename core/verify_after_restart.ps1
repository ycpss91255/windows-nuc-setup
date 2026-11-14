#Requires -Version 5.1
param([string]$ExpectedUserSID)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'entry_os_boundary.ps1')
$currentSID=Get-SetupEntryIdentity
if($ExpectedUserSID -and $ExpectedUserSID -ne $currentSID){throw '提權後帳號已改變，請使用原帳號的管理員權限。'}
. (Join-Path $PSScriptRoot 'paths.ps1')
Initialize-NucReports
$DriverPackagePath=Get-SetupSavedDriverSelection -ResultPath (Resolve-NucPath 'Setup-Result.json')
$confirmation=Get-SetupSavedHardwareConfirmation -ResultPath (Resolve-NucPath 'Setup-Result.json')
$hardware=Get-SetupHardwareProfile -DriverPackagePath $DriverPackagePath @confirmation
$skippedModules=@(@('install_drivers.ps1','apply_amd_privacy_settings.ps1','desktop_icon_layout.ps1')|ForEach-Object {Get-SetupModuleDecision -Module $_ -Hardware $hardware}|Where-Object {-not $_.Applicable})
if(-not (Test-SetupEntryAdministrator)){
 $command="& '"+$PSCommandPath.Replace("'","''")+"' -ExpectedUserSID '"+$currentSID+"'"
 Start-SetupEntryElevated -Command $command;exit
}
& (Resolve-NucPath 'test_setup_prerequisites.ps1') -DriverPackagePath $DriverPackagePath @confirmation
if(($hardware.DriverProfileId -or $hardware.IsNuc8) -and $DriverPackagePath){$hardware|Add-Member -NotePropertyName DriverSelection -NotePropertyValue (New-SetupDriverSelection -PackageRoot $script:NucPackageRoot -DriverPackagePath $DriverPackagePath) -Force}
. (Resolve-NucPath 'after_restart_library.ps1')
Invoke-SetupAfterRestart -Hardware $hardware -DriverPackagePath $DriverPackagePath -Confirmation $confirmation -SkippedModules $skippedModules
