#Requires -Version 5.1
param([switch]$AfterRestart,[switch]$VerifyOnly)
$ErrorActionPreference='Stop'
if($AfterRestart -and $VerifyOnly){throw 'AfterRestart 與 VerifyOnly 不可同時指定。'}
$entry=if($AfterRestart){'Verify-AfterRestart.ps1'}elseif($VerifyOnly){'Verify-Only.ps1'}else{'Configure-NUC.ps1'}
& (Join-Path $PSScriptRoot $entry)
