#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$VerifyOnly,[switch]$SyncOnly,[ValidateSet('All','Hosts','SSH')][string]$Mode='All')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'hosts_sync_library.ps1')
Invoke-SetupHostsSync -RuntimeRoot (Join-Path $env:ProgramData 'CustomHostsSync') -ProfilePath $env:USERPROFILE -UserIdentity ([Security.Principal.WindowsIdentity]::GetCurrent()) -WindowsRoot $env:WINDIR -VerifyOnly:$VerifyOnly -SyncOnly:$SyncOnly -Mode $Mode
