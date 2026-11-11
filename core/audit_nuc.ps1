#Requires -Version 5.1
#Requires -RunAsAdministrator
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'paths.ps1')
. (Join-Path $PSScriptRoot 'audit_library.ps1')
Invoke-SetupAudit -ReportPath (Resolve-NucPath 'Audit-Result.json')