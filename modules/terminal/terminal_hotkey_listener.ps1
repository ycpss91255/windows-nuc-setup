#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'terminal_hotkey_library.ps1')
Invoke-SetupTerminalListener -ModuleRoot $PSScriptRoot