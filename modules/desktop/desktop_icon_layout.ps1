#Requires -Version 5.1

param([ValidateSet('Save','Load','Verify')][string]$Mode='Load',[switch]$Worker,[ValidatePattern('^[a-fA-F0-9-]{36}$')][string]$VerificationRunId,[string]$ExpectedUserSID)
$currentSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($ExpectedUserSID -and $ExpectedUserSID -ne $currentSID){throw '提權後帳號已改變，請使用原帳號儲存或套用桌面排列。'}
if($Mode -ne 'Save' -and (Get-UICulture).Name -ne 'zh-TW'){Write-Host '[略過] 目前桌面排列範本僅適用繁體中文，未套用座標。';[pscustomobject]@{Status='Skipped';Module='desktop_icon_layout.ps1';Reason='目前排列範本使用繁體中文圖示名稱'};return}
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
 $command="& '"+$PSCommandPath.Replace("'","''")+"' -ExpectedUserSID '"+$currentSID+"' -Mode "+$Mode
 if($Worker){$command+=' -Worker'}
 if($VerificationRunId){$command+=" -VerificationRunId '"+$VerificationRunId+"'"}
 Start-Process (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'WindowsPowerShell/v1.0/powershell.exe') -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)));exit
}
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../core/gui_stage_library.ps1')
Invoke-SetupGuiRole -PackageRoot ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))) -Role Icons -Worker:$Worker -VerifyOnly:($Mode -eq 'Verify') -IconMode $Mode -VerificationRunId $VerificationRunId