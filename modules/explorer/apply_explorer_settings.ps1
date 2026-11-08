#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$Worker,[switch]$VerifyOnly)
$ErrorActionPreference='Stop'
$packageRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
. (Join-Path $packageRoot 'core/gui_stage_library.ps1')
Invoke-SetupGuiRole -PackageRoot $packageRoot -Role Explorer -Worker:$Worker -VerifyOnly:$VerifyOnly