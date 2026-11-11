#Requires -Version 5.1
param([ValidateSet('All','Unit','Integration')][string]$Layer='All',[string]$ReportDirectory=(Join-Path ([IO.Path]::GetTempPath()) ('NUC-CI-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'ci_runner_library.ps1')
Invoke-SetupCI -PackageRoot ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))) -ReportDirectory $ReportDirectory -Layer $Layer
