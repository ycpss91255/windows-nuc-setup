#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$VerifyOnly,[switch]$Restore,[string]$VerificationRunId)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'uac_library.ps1')
Invoke-CurrentUserUac -VerifyOnly:$VerifyOnly -Restore:$Restore -VerificationRunId $VerificationRunId|Out-Null