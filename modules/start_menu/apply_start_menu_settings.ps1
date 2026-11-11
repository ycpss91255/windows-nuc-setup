#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$Worker,[switch]$VerifyOnly,[switch]$ApplyPolicy,[switch]$NonInteractive,[ValidatePattern('^[a-fA-F0-9-]{36}$')][string]$VerificationRunId)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../core/gui_stage_library.ps1')
$result=Invoke-SetupGuiRole -PackageRoot ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))) -Role Start -Worker:$Worker -VerifyOnly:$VerifyOnly -ApplyPolicy:$ApplyPolicy -NonInteractive:$NonInteractive -VerificationRunId $VerificationRunId
if($result.Success){Write-Host '已由原生匯出確認開始選單釘選清空。' -ForegroundColor Green}
elseif($result.Status -eq 'LegacyPendingApply'){Write-Warning '開始選單政策待處理：其他設定全部完成後，才可明確同意套用舊版政策。'}
else{Write-Warning '開始選單政策已準備，但原生匯出尚未確認釘選清空；請完成其餘工作後手動重新登入，再執行 windows.cmd -AfterRestart。'}
$result