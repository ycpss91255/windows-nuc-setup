#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$Worker,[string]$SourcePackageRoot,[switch]$VerifyOnly,[ValidatePattern('^[a-fA-F0-9-]{36}$')][string]$VerificationRunId)
$ErrorActionPreference='Stop'
$packageRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if($SourcePackageRoot -and [IO.Path]::GetFullPath($SourcePackageRoot) -ine $packageRoot){throw '桌面原始套件位置必須與公開入口相符。'}
. (Join-Path $PSScriptRoot '../../core/gui_stage_library.ps1')
Invoke-SetupGuiRole -PackageRoot $packageRoot -Role Desktop -Worker:$Worker -VerifyOnly:$VerifyOnly -VerificationRunId $VerificationRunId