#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$VerifyOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'terminal_hotkey_library.ps1')
Invoke-SetupTerminalHotkey -ModuleRoot $PSScriptRoot -VerifyOnly:$VerifyOnly