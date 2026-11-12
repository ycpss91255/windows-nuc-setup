#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $root 'script/test/test_report.ps1')
. (Join-Path $root 'script/report/portal.ps1')
if(-not $env:PORTAL_TEST_ARCHIVE -or -not $env:PORTAL_TEST_SOURCE -or -not $env:WINDOWS_SETUP_REPORT_BUNDLE_TOOL){throw 'Explicit historical test fixture inputs are required.'}
$entry=[pscustomobject]@{Version='v0.2.4';Commit='0a87e84fa51b97fbc263c12964792bdbfdf69d8a';Immutable=$true;Repository='ycpss91255/windows_setup';ArchivePath=$env:PORTAL_TEST_ARCHIVE;ArchiveDigest='sha256:435c48d8eeee6eb6a9cc12791487f8fed574144c9fccdd01503792d52ba80a04';ArchiveSize=811070;SourcePath=$env:PORTAL_TEST_SOURCE;SnapshotPath='';ManifestPath='';ReleaseUrl='https://github.com/ycpss91255/windows_setup/releases/tag/v0.2.4'}
$evidence=Test-PortalReleaseEvidence $entry
if($evidence.SnapshotDigest -cne 'sha256:906b709cfcbac5269800aea42b28da116a24e6bfa1c1a9a623e84652f305bf1e' -or $evidence.ArchiveDigest -cne $entry.ArchiveDigest){throw 'Verified summary or archive digest differs.'}
function Reject([scriptblock]$action,[string]$message){$caught=$false;try{& $action|Out-Null}catch{$caught=$true};if(-not $caught){throw $message}}
$wrong=$entry|Select-Object *;$wrong.ArchiveDigest='sha256:'+('0'*64)
Reject {Test-PortalReleaseEvidence $wrong} 'incorrect outer digest was accepted'
$wrong=$entry|Select-Object *;$wrong.ArchiveSize=1
Reject {Test-PortalReleaseEvidence $wrong} 'incorrect outer size was accepted'
$wrong=$entry|Select-Object *;$wrong.Commit=('a'*40)
Reject {Test-PortalReleaseEvidence $wrong} 'incorrect source commit was accepted'
$wrong=$entry|Select-Object *;$wrong.Repository='other/repository'
Reject {Test-PortalReleaseEvidence $wrong} 'different repository was accepted'
$wrong=$entry|Select-Object *;$wrong.Immutable=$false
Reject {Test-PortalReleaseEvidence $wrong} 'mutable release was accepted'
$wrong=$entry|Select-Object *;$wrong.ReleaseUrl='https://github.com/other/repo/releases/tag/v0.2.4'
Reject {Test-PortalReleaseEvidence $wrong} 'incorrect release URL was accepted'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('portal_zip_check_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $fixture|Out-Null
$catalog=Join-Path $fixture 'catalog.json'
ConvertTo-Json -InputObject @($entry) -Depth 8|Set-Content -LiteralPath $catalog -Encoding UTF8
& (Join-Path $root 'script/report/build_portal.ps1') -Preview -CatalogPath $catalog -OutputDirectory (Join-Path $fixture 'pages')|Out-Null
$published=Get-Content -LiteralPath (Join-Path $fixture 'pages/versions.json') -Raw -Encoding UTF8|ConvertFrom-Json
if($published.Status -cne 'Verified' -or $published.Digest -cne $evidence.SnapshotDigest -or $published.ArchiveDigest -cne $entry.ArchiveDigest){throw 'Published version digest fields differ.'}
if((Get-FileHash -LiteralPath (Join-Path $fixture 'pages/versions/v0.2.4/go_coverage.out')).Hash.ToLowerInvariant() -cne 'e48d385c99419005fd3c134a5a93790b78d84b22d05749af085bb35df657b2cd'){throw 'Published historical profile differs.'}
