#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$VerifyOnly,[string]$VerificationRunId)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'debloat_library.ps1')
Invoke-SetupDebloat -ModuleRoot $PSScriptRoot -VerifyOnly:$VerifyOnly -VerificationRunId $VerificationRunId|Out-Null
if(-not $VerifyOnly){
 . (Join-Path $PSScriptRoot '../privacy/privacy_library.ps1')
 Invoke-CurrentUserPrivacy|Out-Null
}
Write-Host 'Win11Debloat 清理與適用功能登錄讀回完成。' -ForegroundColor Green