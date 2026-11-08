#Requires -Version 5.1
param([ValidatePattern('^[a-fA-F0-9-]{36}$')][string]$VerificationRunId=([guid]::NewGuid().ToString()),[string]$ExpectedUserSID)
$ErrorActionPreference='Stop'
$currentSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($ExpectedUserSID -and $ExpectedUserSID -ne $currentSID){throw '提權後帳號已改變，請使用原帳號的管理員權限。'}
. (Join-Path $PSScriptRoot 'paths.ps1')
. (Join-Path $PSScriptRoot 'verification.ps1')
. (Resolve-NucPath 'ssh_firewall.ps1')
Initialize-NucReports
$DriverPackagePath=Get-SetupSavedDriverSelection -ResultPath (Resolve-NucPath 'Setup-Result.json')
$confirmation=Get-SetupSavedHardwareConfirmation -ResultPath (Resolve-NucPath 'Setup-Result.json')
$hardware=Get-SetupHardwareProfile -DriverPackagePath $DriverPackagePath @confirmation
$p=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
 $command="& '"+$PSCommandPath.Replace("'","''")+"' -ExpectedUserSID '"+$currentSID+"'"
 $command+=" -VerificationRunId '"+$VerificationRunId+"'"
 Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)));exit
}
. (Resolve-NucPath 'update_stage_library.ps1')
. (Join-Path $PSScriptRoot 'verification_library.ps1')
Invoke-SetupVerification -Hardware $hardware -DriverPackagePath $DriverPackagePath -VerificationRunId $VerificationRunId
