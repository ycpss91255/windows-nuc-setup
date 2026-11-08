#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$PublicDirectory,[Parameter(Mandatory=$true)][string]$CoverageDirectory,[switch]$PreparingRelease)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'test_report.ps1')
. (Join-Path $PSScriptRoot '../report/portal.ps1')
$report=Get-Content -LiteralPath (Join-Path $PublicDirectory 'summary.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert-TestReportSnapshot $report
if($report.RefType -ceq 'Release'){
 if(-not $PreparingRelease -or $report.SchemaVersion -ne 2 -or $report.PSObject.Properties['GoCoverage'] -or $report.PSObject.Properties['RepoCoverage'] -or $report.Coverage -cne 'NotMeasured' -or (Test-Path -LiteralPath (Join-Path $PublicDirectory 'go_coverage.out')) -or (Test-Path -LiteralPath (Join-Path $PublicDirectory 'go_coverage.json'))){throw '只允許為尚未附加量測的本機 schema2 發布準備加入 Go 證據；既有版本與工件不改寫。'}
}elseif($PreparingRelease){throw '發布準備旗標只適用於 Tag staging。'}
$coverage=Get-Content -LiteralPath (Join-Path $CoverageDirectory 'go_coverage.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert-GoCoverage -Coverage $coverage -Report $report
Assert-GoCoverageProfile -Coverage $coverage -Directory $CoverageDirectory
if($PreparingRelease -and $coverage.Covered*100 -lt $coverage.TotalStatements*80){throw '發布準備的 Go 覆蓋率不得低於精確八成。'}
$report|Add-Member -NotePropertyName GoCoverage -NotePropertyValue $coverage -Force
Write-SnapshotView -Snapshot $report -OutputDirectory $PublicDirectory
$source=[IO.Path]::GetFullPath((Join-Path $CoverageDirectory 'go_coverage.out'))
$destination=[IO.Path]::GetFullPath((Join-Path $PublicDirectory 'go_coverage.out'))
if($source -ine $destination){Copy-Item -LiteralPath $source -Destination $destination}
