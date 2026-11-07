#Requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'test_report.ps1')
if(Test-Path -LiteralPath $OutputDirectory){throw 'Fixture output must be new.'}
New-Item -ItemType Directory -Path $OutputDirectory|Out-Null
$checks=@(
 [pscustomobject]@{Name='fixture_unit';Layer='Unit';Status='Passed';Executed=$true;Passed=$true;ExitCode=0;DurationSeconds=0;Assertions=@([pscustomobject]@{Name='synthetic';Passed=$true})},
 [pscustomobject]@{Name='fixture_integration';Layer='Integration';Status='Passed';Executed=$true;Passed=$true;ExitCode=0;DurationSeconds=0;Assertions=@([pscustomobject]@{Name='synthetic';Passed=$true})},
 [pscustomobject]@{Name='fixture_system';Layer='System';Status='NotRun';Executed=$false;Passed=$null;ExitCode=$null;DurationSeconds=0;Assertions=@()},
 [pscustomobject]@{Name='fixture_e2e';Layer='System E2E';Status='NotRun';Executed=$false;Passed=$null;ExitCode=$null;DurationSeconds=0;Assertions=@()}
)
$snapshot=Join-Path $OutputDirectory 'synthetic_snapshot'
Write-TestReports -Checks $checks -OutputDirectory $snapshot -Layer All -Commit ('f'*40) -RunUrl 'https://github.com/example/fixture/actions/runs/1' -SourceState Clean -Version v9.9.9 -Environment 'Synthetic acceptance fixture, not real main evidence' -RefType Branch -RefName main -Changes @('Synthetic fixture only')|Out-Null
$catalog=Join-Path $OutputDirectory 'catalog.json'
ConvertTo-Json -InputObject @([pscustomobject]@{Version='v0.1.0';Commit=('e'*40);ReleaseUrl='https://github.com/example/fixture/releases/tag/v0.1.0';Immutable=$false;SnapshotPath='';ManifestPath='';SnapshotDigest=''})|Set-Content -LiteralPath $catalog -Encoding UTF8
& (Join-Path $PSScriptRoot '../report/build_portal.ps1') -CatalogPath $catalog -MainSnapshotPath (Join-Path $snapshot 'summary.json') -OutputDirectory (Join-Path $OutputDirectory 'portal')|Out-Null
