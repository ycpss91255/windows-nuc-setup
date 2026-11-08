#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$PublicDirectory,[Parameter(Mandatory=$true)][string]$CoverageDirectory,[string]$CoverageToolPath=$env:WINDOWS_SETUP_COVERAGE_TOOL,[string]$SourceRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'test_report.ps1')
. (Join-Path $PSScriptRoot '../report/portal.ps1')
$report=Get-Content -LiteralPath (Join-Path $PublicDirectory 'summary.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert-TestReportSnapshot $report
if($report.SchemaVersion -ne 2){throw '只允許附加本次schema2量測，不改寫歷史附件。'}
$coverage=Get-Content -LiteralPath (Join-Path $CoverageDirectory 'repo_coverage.json') -Raw -Encoding UTF8|ConvertFrom-Json
$report|Add-Member -NotePropertyName RepoCoverage -NotePropertyValue $coverage -Force
$report.Coverage=if($coverage.Result.Complete){'Measured'}else{'NotMeasured'}
Assert-RepoCoverageArtifacts -Report $report -Directory $CoverageDirectory -CoverageToolPath $CoverageToolPath -SourceRoot $SourceRoot -RequireComplete
Write-SnapshotView -Snapshot $report -OutputDirectory $PublicDirectory
foreach($name in @('repo_coverage.json','coverage_inventory.json','coverage.xml')){
 $source=[IO.Path]::GetFullPath((Join-Path $CoverageDirectory $name));$destination=[IO.Path]::GetFullPath((Join-Path $PublicDirectory $name))
 if($source -ine $destination){Copy-Item -LiteralPath $source -Destination $destination}
}
