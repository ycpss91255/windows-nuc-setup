#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
. (Join-Path $root 'test/powershell/helpers/report_bundle_fixture.ps1')
$parent=Join-Path ([IO.Path]::GetTempPath()) ('publish_runtime_fixture_'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($parent)
$fixture=New-TestReportBundleFixture -RepositoryRoot $root -Destination (Join-Path $parent 'fixture') -Runtime
$f=$fixture.Metadata;$public=Join-Path $fixture.Root 'windows-test-reports-1-1'
$drivers=Join-Path $parent 'drivers.json';[IO.File]::WriteAllText($drivers,'{"SchemaVersion":1,"Releases":[]}')
function gh {throw 'LOCAL_GH_BOUNDARY_ONLY'}
$reached=$false
try {
 & (Join-Path $root 'script/report/publish_quality_release.ps1') -PublicDirectory $public -Version $f.version -Commit $f.commit -NotesPath (Join-Path $public 'summary.md') -Repository example/windows_setup -CoverageToolPath $fixture.CoverageTool -DriverAssetManifestPath $drivers
} catch {$reached=$_.Exception.Message -ceq 'LOCAL_GH_BOUNDARY_ONLY';if(-not $reached){Write-Host $_.Exception.Message}} finally {Remove-Item Function:\gh}
if(-not $reached){throw 'runtime release failed before the local GitHub boundary'}
Write-Host '@@ASSERT@@{"Name":"runtime release validates without Go coverage before GitHub boundary","Passed":true}'
