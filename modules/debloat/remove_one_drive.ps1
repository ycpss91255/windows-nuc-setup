#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$VerifyOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'one_drive_library.ps1')
Invoke-OneDriveRemovalEntry -VerifyOnly:$VerifyOnly