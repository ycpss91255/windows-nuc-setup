#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$VerifyOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'residue_library.ps1')
Invoke-SetupResidueCleanup -SystemRoot $env:SystemDrive -UserProfile $env:USERPROFILE -ResultRoot (Join-Path $env:ProgramData 'NUC8-Setup') -UserSid ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value) -VerifyOnly:$VerifyOnly
