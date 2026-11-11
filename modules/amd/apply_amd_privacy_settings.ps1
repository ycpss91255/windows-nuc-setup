#Requires -RunAsAdministrator
param([switch]$VerifyOnly)
. (Join-Path $PSScriptRoot 'amd_privacy_library.ps1')
Invoke-SetupAmdPrivacy -VerifyOnly:$VerifyOnly -EntryPath $PSCommandPath -ModuleRoot $PSScriptRoot
