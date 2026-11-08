#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$Worker)
. (Join-Path $PSScriptRoot 'update_entry_library.ps1')
Invoke-SetupWindowsUpdateEntry -EntryPath $PSCommandPath -ModuleRoot $PSScriptRoot -Worker:$Worker
