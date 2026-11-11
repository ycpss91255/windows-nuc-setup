#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$Worker,[switch]$VerifyOnly,[ValidatePattern('^[a-fA-F0-9-]{36}$')][string]$VerificationRunId)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../core/gui_stage_library.ps1')
$result=Invoke-SetupGuiRole -PackageRoot ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))) -Role Theme -Worker:$Worker -VerifyOnly:$VerifyOnly -VerificationRunId $VerificationRunId
$result|Add-Member -NotePropertyName VerificationRunId -NotePropertyValue $VerificationRunId -Force
$result