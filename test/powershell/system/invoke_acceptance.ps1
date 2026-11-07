#Requires -Version 5.1
param([switch]$RunOnThisComputer)
$ErrorActionPreference='Stop'
if(-not $RunOnThisComputer){
 [pscustomobject]@{Layer='System';Status='NotRun';Executed=$false;FullInstallationE2E='NotRun';Reason='需在目標測試機明確指定 -RunOnThisComputer；此入口只驗收既有設定。'}
 return
}
$principal=[Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if(-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw '請在目標測試機以系統管理員 PowerShell 執行；此入口不自動提權。'}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$started=Get-Date
& (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'core\verify_only.ps1')
if($LASTEXITCODE -ne 0){throw '實機驗收執行失敗；未標記為通過。'}
$path=Join-Path $root 'reports\Verification-Result.json'
if(-not(Test-Path -LiteralPath $path) -or (Get-Item -LiteralPath $path).LastWriteTime -lt $started){throw '未產生本輪驗收報告，拒絕沿用舊結果。'}
$report=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
if($report.Computer -ne $env:COMPUTERNAME){throw '驗收報告電腦不符。'}
[pscustomobject]@{Layer='System';Status=$(if($report.Passed){'Passed'}else{'Failed'});Executed=$true;FullInstallationE2E='NotRun';ReportPath=$path}
if(-not $report.Passed){throw '既有設定尚未全部通過驗收；本次不代表完整安裝 E2E。'}