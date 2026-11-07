#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$PublicDirectory,[Parameter(Mandatory=$true)][string]$CoverageDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'test_report.ps1')
. (Join-Path $PSScriptRoot '../report/portal.ps1')
$report=Get-Content -LiteralPath (Join-Path $PublicDirectory 'summary.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert-TestReportSnapshot $report
if($report.RefType -cne 'Branch'){throw 'Go 附件只用於分支報告；不可改寫不可變 Release 契約。'}
$coverage=Get-Content -LiteralPath (Join-Path $CoverageDirectory 'go_coverage.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert-GoCoverage -Coverage $coverage -Report $report
Assert-GoCoverageProfile -Coverage $coverage -Directory $CoverageDirectory
$report|Add-Member -NotePropertyName GoCoverage -NotePropertyValue $coverage -Force
Write-SnapshotView -Snapshot $report -OutputDirectory $PublicDirectory
$source=[IO.Path]::GetFullPath((Join-Path $CoverageDirectory 'go_coverage.out'))
$destination=[IO.Path]::GetFullPath((Join-Path $PublicDirectory 'go_coverage.out'))
if($source -ine $destination){Copy-Item -LiteralPath $source -Destination $destination}