#Requires -Version 5.1
#Requires -RunAsAdministrator
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../core/gui_stage_library.ps1')
. (Join-Path $PSScriptRoot 'taskbar_stage_library.ps1')
Invoke-SetupTaskbarFinalizePending