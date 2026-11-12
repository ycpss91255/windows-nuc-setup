#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $root 'script/test/test_report.ps1')
. (Join-Path $root 'script/report/portal.ps1')
if(-not $env:PORTAL_TEST_ARCHIVE -or -not $env:PORTAL_TEST_SOURCE -or -not $env:WINDOWS_SETUP_REPORT_BUNDLE_TOOL){throw 'Explicit historical test fixture inputs are required.'}
$entry=[pscustomobject]@{Version='v0.2.4';Commit='0a87e84fa51b97fbc263c12964792bdbfdf69d8a';Immutable=$true;Repository='ycpss91255/windows_setup';ArchivePath=$env:PORTAL_TEST_ARCHIVE;ArchiveDigest='sha256:435c48d8eeee6eb6a9cc12791487f8fed574144c9fccdd01503792d52ba80a04';ArchiveSize=811070;SourcePath=$env:PORTAL_TEST_SOURCE;SnapshotPath='';ManifestPath=''}
$evidence=Test-PortalReleaseEvidence $entry
if($evidence.SnapshotDigest -cne 'sha256:906b709cfcbac5269800aea42b28da116a24e6bfa1c1a9a623e84652f305bf1e' -or $evidence.ArchiveDigest -cne $entry.ArchiveDigest){throw 'Verified summary or archive digest differs.'}
