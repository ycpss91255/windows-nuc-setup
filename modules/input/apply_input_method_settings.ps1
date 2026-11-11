#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$VerifyOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'input_method_library.ps1')
Invoke-SetupInputMethodSettings -VerifyOnly:$VerifyOnly