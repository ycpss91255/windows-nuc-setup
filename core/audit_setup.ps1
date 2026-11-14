#Requires -Version 5.1
#Requires -RunAsAdministrator
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'audit_entry_library.ps1')
Invoke-SetupAuditEntry
