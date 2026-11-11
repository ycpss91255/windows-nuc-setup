#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$VerifyOnly,[string]$VerificationRunId)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'privacy_library.ps1')
Invoke-CurrentUserPrivacy -VerifyOnly:$VerifyOnly -VerificationRunId $VerificationRunId|Out-Null
