#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$Worker,[switch]$VerifyOnly,[ValidatePattern('^[a-fA-F0-9-]{36}$')][string]$VerificationRunId)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../core/gui_stage_library.ps1')
$result=Invoke-SetupGuiRole -PackageRoot ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))) -Role Taskbar -Worker:$Worker -VerifyOnly:$VerifyOnly -VerificationRunId $VerificationRunId
if(-not $VerifyOnly){Write-Host '工作列設定已寫入：天氣/小工具關閉、搜尋欄隱藏、預設釘選只保留 Edge。';Write-Host '按 Windows 鍵直接輸入搜尋仍可使用。釘選配置在下次登入時套用；本工具不會自動登出或重新開機。'}
$result