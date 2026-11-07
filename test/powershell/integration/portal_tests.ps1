#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
. (Join-Path $root 'script/test/test_report.ps1')
. (Join-Path $root 'script/report/portal.ps1')
$count=0
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Message)};$script:count++;Write-Host ('PASS: '+$Message)}
function Refuse([scriptblock]$Action,[string]$Message){$caught=$false;try{& $Action|Out-Null}catch{$caught=$true};Assert $caught $Message}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('windows_portal_'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory $fixture|Out-Null
$checks=@([pscustomobject]@{Name='Unit.Example';Layer='Unit';Status='Passed';Executed=$true;Passed=$true;ExitCode=0;DurationSeconds=0.5;Assertions=@([pscustomobject]@{Name='stable';Passed=$true})},[pscustomobject]@{Name='Integration.Example';Layer='Integration';Status='Passed';Executed=$true;Passed=$true;ExitCode=0;DurationSeconds=0.5;Assertions=@([pscustomobject]@{Name='old-case';Passed=$true})},[pscustomobject]@{Name='System';Layer='System';Status='NotRun';Executed=$false;Passed=$null;ExitCode=$null;Assertions=@()},[pscustomobject]@{Name='System E2E';Layer='System E2E';Status='NotRun';Executed=$false;Passed=$null;ExitCode=$null;Assertions=@()})
function MakeEvidence([string]$Version,[string]$SHA,[string]$OldHtml){
 $dir=Join-Path $fixture $Version
 $report=Write-TestReports -Checks $checks -OutputDirectory $dir -Layer All -Commit $SHA -RunUrl 'https://github.com/example/repo/actions/runs/42' -SourceState Clean -Version $Version -Environment 'Windows fixture / PowerShell 5.1' -RefType Release -RefName $Version -MeasuredAt '2026-11-07T00:00:00Z' -Changes @('fixture change')
 if($OldHtml){[IO.File]::WriteAllText((Join-Path $dir 'index.html'),$OldHtml,[Text.UTF8Encoding]::new($false))}
 Copy-Item (Join-Path $dir 'summary.json') (Join-Path $dir 'quality.json')
 $files=@('index.html','summary.json','summary.md','junit.xml','unit.svg','integration.svg','system.svg','coverage.svg')
 $manifest=@{SchemaVersion=1;Version=$Version;Commit=$SHA;SnapshotSHA256=(Get-FileHash (Join-Path $dir 'quality.json')).Hash.ToLowerInvariant();Files=@($files|ForEach-Object {@{Name=$_;SHA256=(Get-FileHash (Join-Path $dir $_)).Hash.ToLowerInvariant()}})}
 $manifest|ConvertTo-Json -Depth 6|Set-Content (Join-Path $dir 'quality-manifest.json') -Encoding UTF8
 [pscustomobject]@{Version=$Version;Commit=$SHA;ReleaseUrl=('https://github.com/example/repo/releases/tag/'+$Version);Immutable=$true;SnapshotPath=(Join-Path $dir 'quality.json');ManifestPath=(Join-Path $dir 'quality-manifest.json');SnapshotDigest=('sha256:'+$manifest.SnapshotSHA256);ManifestDigest=('sha256:'+(Get-FileHash (Join-Path $dir 'quality-manifest.json')).Hash.ToLowerInvariant());AssetDirectory=$dir;AssetDigests=@(Get-ChildItem $dir -File|ForEach-Object {[pscustomobject]@{Name=$_.Name;Digest=('sha256:'+(Get-FileHash $_.FullName).Hash.ToLowerInvariant())}})}
}
$a=MakeEvidence 'v1.0.0' ('a'*40) '<!doctype html><meta charset="utf-8"><h1>old renderer evidence</h1>'
$b=MakeEvidence 'v1.0.1' ('b'*40) ''
$valid=Test-PortalReleaseEvidence $a
Assert ($valid.Snapshot.MeasuredAt -eq '2026-11-07T00:00:00Z') 'release measurement time remains original'
$old=$a.Commit;$a.Commit='c'*40;Refuse {Test-PortalReleaseEvidence $a} 'wrong tag SHA rejects evidence';$a.Commit=$old
$old=$a.SnapshotDigest;$a.SnapshotDigest='sha256:'+('0'*64);Refuse {Test-PortalReleaseEvidence $a} 'wrong GitHub asset digest rejects evidence';$a.SnapshotDigest=$old
$old=$a.ManifestDigest;$a.ManifestDigest='sha256:'+('0'*64);Refuse {Test-PortalReleaseEvidence $a} 'wrong manifest digest rejects evidence';$a.ManifestDigest=$old
$a.Immutable=$false;Refuse {Test-PortalReleaseEvidence $a} 'mutable release cannot claim immutable evidence';$a.Immutable=$true
$unknown=[pscustomobject]@{Version='v0.1.0';Commit=('d'*40);ReleaseUrl='https://github.com/example/repo/releases/tag/v0.1.0';Immutable=$false;SnapshotPath='';ManifestPath='';SnapshotDigest=''}
$catalog=Join-Path $fixture 'catalog.json';@($a,$b,$unknown)|ConvertTo-Json -Depth 12|Set-Content $catalog -Encoding UTF8
$mainDir=Join-Path $fixture 'main'
$null=Write-TestReports -Checks $checks -OutputDirectory $mainDir -Layer All -Commit ('e'*40) -RunUrl 'https://github.com/example/repo/actions/runs/43' -SourceState Clean -Version v1.0.1 -Environment 'Windows fixture / PowerShell 5.1' -RefType Branch -RefName main -MeasuredAt '2026-11-07T01:00:00Z' -Changes @('new main')
$portal1=Join-Path $fixture 'portal1'; & (Join-Path $root 'script/report/build_portal.ps1') -CatalogPath $catalog -OutputDirectory $portal1 -MainSnapshotPath (Join-Path $mainDir 'summary.json')|Out-Null
Assert ((Get-FileHash (Join-Path $portal1 'versions/v1.0.0/index.html')).Hash -eq (Get-FileHash (Join-Path $a.AssetDirectory 'index.html')).Hash) 'historical renderer bytes preserved without regeneration'
Assert (((Get-Content (Join-Path $portal1 'versions.json') -Raw -Encoding UTF8|ConvertFrom-Json)|Where-Object Version -eq 'v0.1.0').Status -eq 'Unknown') 'old release without evidence retains Unknown data status'
$null=Write-TestReports -Checks $checks -OutputDirectory $mainDir -Layer All -Commit ('f'*40) -RunUrl 'https://github.com/example/repo/actions/runs/44' -SourceState Clean -Version v1.0.1 -Environment 'Windows fixture / PowerShell 5.1' -RefType Branch -RefName main -MeasuredAt '2026-11-07T02:00:00Z' -Changes @('later main')
$portal2=Join-Path $fixture 'portal2'; & (Join-Path $root 'script/report/build_portal.ps1') -CatalogPath $catalog -OutputDirectory $portal2 -MainSnapshotPath (Join-Path $mainDir 'summary.json')|Out-Null
foreach($version in @('v1.0.0','v1.0.1')){Assert ((Get-FileHash (Join-Path $portal1 ('versions/'+$version+'/index.html'))).Hash -eq (Get-FileHash (Join-Path $portal2 ('versions/'+$version+'/index.html'))).Hash) ('latest update preserves distinct-version renderer bytes: '+$version)}
$first=Get-Content $a.SnapshotPath -Raw -Encoding UTF8|ConvertFrom-Json;$second=Get-Content $b.SnapshotPath -Raw -Encoding UTF8|ConvertFrom-Json
$first.Checks[0].Assertions=@([pscustomobject]@{Name='fixed';Passed=$false},[pscustomobject]@{Name='new-fail';Passed=$true},[pscustomobject]@{Name='removed';Passed=$true})
$second.Checks[0].Assertions=@([pscustomobject]@{Name='fixed';Passed=$true},[pscustomobject]@{Name='new-fail';Passed=$false},[pscustomobject]@{Name='added';Passed=$true})
$diff=Compare-TestSnapshots $first $second
Assert ($diff.Status -eq 'Compared' -and $diff.Added.Count -eq 1 -and $diff.Removed.Count -eq 1 -and $diff.NewFailures.Count -eq 1 -and $diff.Fixed.Count -eq 1 -and $diff.NotRun.Count -gt 0) 'two-version comparison computes added removed failures fixes and not-run'
$second.Checks[1].Passed=$false;$second.Checks[1].Status='Failed';$second.Checks[1].ExitCode=1
Assert (@((Compare-TestSnapshots $first $second).NewFailures|Where-Object {$_ -like '*[[]suite execution[]]*'}).Count -eq 1) 'suite crash remains a failure even if emitted assertions passed'
$second.RequestedLayer='Unit';Assert ((Compare-TestSnapshots $first $second).Status -eq 'Unknown') 'incompatible scope cannot become a false diff'
Assert ((Compare-TestSnapshots $first $null).Status -eq 'Unknown') 'missing baseline produces Unknown'
Assert ((Get-Content (Join-Path $portal1 'compare.js') -Raw).Contains("if(data.Status!=='Compared')return")) 'Unknown comparison does not display false zero counts'
# A corrupted historical attachment is Invalid, not Verified, without blocking other versions.
[IO.File]::AppendAllText((Join-Path $a.AssetDirectory 'index.html'),'tampered')
$portal3=Join-Path $fixture 'portal3'; & (Join-Path $root 'script/report/build_portal.ps1') -CatalogPath $catalog -OutputDirectory $portal3|Out-Null
$versions=Get-Content (Join-Path $portal3 'versions.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert (($versions|Where-Object Version -eq 'v1.0.0').Status -eq 'Invalid' -and ($versions|Where-Object Version -eq 'v1.0.1').Status -eq 'Verified') 'corrupt version is Invalid while valid history remains available'
# Parameterized tests can emit duplicate display names: retain evidence but refuse ambiguous comparisons.
$savedAssertions=$checks[0].Assertions
$checks[0].Assertions=@([pscustomobject]@{Name='VerifyOnly rejects incomplete state';Passed=$true},[pscustomobject]@{Name='VerifyOnly rejects incomplete state';Passed=$true})
$duplicate=MakeEvidence 'v1.0.2' ('9'*40) ''
$duplicateSnapshot=Get-Content $duplicate.SnapshotPath -Raw -Encoding UTF8|ConvertFrom-Json
$comparison=Compare-TestSnapshots $duplicateSnapshot $duplicateSnapshot
Assert ($comparison.Status -eq 'Unknown' -and $comparison.Reason.Contains('重複測試識別') -and -not $comparison.Added.Count) 'duplicate assertion names produce explicit Unknown without deduplication'
$duplicateCatalog=Join-Path $fixture 'duplicate_catalog.json'
ConvertTo-Json -InputObject @($duplicate) -Depth 12|Set-Content $duplicateCatalog -Encoding UTF8
$duplicatePortal=Join-Path $fixture 'duplicate_portal'
& (Join-Path $root 'script/report/build_portal.ps1') -CatalogPath $duplicateCatalog -MainSnapshotPath (Join-Path $mainDir 'summary.json') -OutputDirectory $duplicatePortal|Out-Null
$comparisonFile=Get-Content (Join-Path $duplicatePortal 'comparisons/v1.0.2--v1.0.2.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert ($comparisonFile.Status -eq 'Unknown' -and (Test-Path (Join-Path $duplicatePortal 'main/unit.svg'))) 'ambiguous release comparison does not block main report deployment'
$preserved=Get-Content (Join-Path $duplicatePortal 'versions/v1.0.2/summary.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert ($preserved.Checks[0].Assertions.Count -eq 2) 'both measured assertions remain in immutable evidence'
$checks[0].Assertions=$savedAssertions
# Mock GitHub only: exercise the real draft/upload verification/publish ordering.
$publish=Join-Path $root 'script/report/publish_quality_release.ps1'
$notes=Join-Path $fixture 'notes.md';[IO.File]::WriteAllText($notes,'fixture notes')
function gh {
 $words=@($args);$global:LASTEXITCODE=0
 if($words[0] -eq 'api' -and $words -contains '--paginate'){return}
 if($words[0] -eq 'release' -and $words[1] -eq 'create'){
  $global:portalDraftRequested=$words -contains '--draft'
  $allowed=@('quality.json','quality-manifest.json','index.html','summary.md','junit.xml','unit.svg','integration.svg','system.svg','coverage.svg')
  $global:portalMockAssets=@($words|Where-Object {[IO.Path]::GetFileName([string]$_) -in $allowed}|ForEach-Object {@{name=[IO.Path]::GetFileName($_);digest=('sha256:'+(Get-FileHash -LiteralPath $_).Hash.ToLowerInvariant())}})
  return
 }
 if($words[0] -eq 'release' -and $words[1] -eq 'view'){
  if($global:portalMockMode -eq 'bad-digest'){$global:portalMockAssets[0].digest='sha256:'+('0'*64)}
  return (@{isDraft=$true;assets=$global:portalMockAssets}|ConvertTo-Json -Depth 5)
 }
 if($words[0] -eq 'release' -and $words[1] -eq 'edit'){$global:portalPublished++;return}
 if($words[0] -eq 'api' -and $words[1] -like '*/releases/tags/*'){
  $immutable=if($global:portalMockMode -eq 'string-immutable'){'true'}else{$global:portalMockMode -ne 'mutable'}
  $assets=if($global:portalMockMode -eq 'missing-asset'){@($global:portalMockAssets|Select-Object -Skip 1)}else{$global:portalMockAssets}
  return (@{immutable=$immutable;draft=$false;tag_name='v1.0.1';assets=$assets;html_url='https://github.com/example/repo/releases/tag/v1.0.1'}|ConvertTo-Json -Depth 5)
 }
 if($words[0] -eq 'api' -and $words[1] -like '*/commits/*'){return $(if($global:portalMockMode -eq 'wrong-tag-sha'){'c'*40}else{'b'*40})}
 throw ('Unexpected mock GitHub call: '+($words -join ' '))
}
foreach($mode in @('success','bad-digest','mutable','string-immutable','missing-asset','wrong-tag-sha')){
 $global:portalMockMode=$mode;$global:portalPublished=0;$global:portalDraftRequested=$false
 $accepted=$true;try{& $publish -PublicDirectory $b.AssetDirectory -Version $b.Version -Commit $b.Commit -NotesPath $notes -Repository example/repo|Out-Null}catch{$accepted=$false}
 Assert ($accepted -eq ($mode -eq 'success')) ('release accepts only verified immutable publication: '+$mode)
 Assert $global:portalDraftRequested ('release uses draft before upload verification: '+$mode)
 Assert ($global:portalPublished -eq $(if($mode -eq 'bad-digest'){0}else{1})) ('bad attachment digest cannot reach publish: '+$mode)
}
Remove-Item Function:\gh
Write-Host ('ALL PASS: '+$count+' portal evidence and comparison assertions; local fixtures only.')

# User-facing conclusions follow real main evidence; JSON keeps machine statuses.
$landing=Get-Content (Join-Path $portal1 'index.html') -Raw -Encoding UTF8
Assert ($landing.Contains('目前程式檢查通過') -and $landing.Contains('eeeeeee') -and $landing.Contains('2026-11-07 01:00:00 UTC')) '首頁直接呈現本次通過結論與來源時間'
Assert ($landing.Contains('完整安裝尚未實測') -and $landing.Contains('blob/main/readme.md') -and $landing.Contains('main/index.html')) '首頁保留未實測限制與操作及明細入口'
Assert ($landing.Contains('<summary>舊版本與進階比較</summary>') -and $landing.Contains('未保存測試紀錄') -and -not $landing.Contains('Unknown')) '舊版本缺紀錄以中文顯示並放次要折疊區'
$empty=Get-Content (Join-Path $portal3 'index.html') -Raw -Encoding UTF8
Assert ($empty.Contains('尚無本次報告') -and -not $empty.Contains('目前程式檢查通過')) '沒有本次證據不顯示通過'
$failedChecks=$checks|ConvertTo-Json -Depth 12|ConvertFrom-Json
$failedChecks[0].Status='Failed';$failedChecks[0].Passed=$false;$failedChecks[0].ExitCode=1;$failedChecks[0].Assertions[0].Passed=$false
$failedDir=Join-Path $fixture 'failed_main'
$null=Write-TestReports -Checks $failedChecks -OutputDirectory $failedDir -Layer All -Commit ('8'*40) -RunUrl 'https://github.com/example/repo/actions/runs/45' -SourceState Clean -Version v1.0.1 -Environment 'Windows fixture / PowerShell 5.1' -RefType Branch -RefName main -MeasuredAt '2026-11-07T03:00:00Z'
$emptyCatalog=Join-Path $fixture 'empty_catalog.json';[IO.File]::WriteAllText($emptyCatalog,'[]')
$failedPortal=Join-Path $fixture 'failed_portal'
& (Join-Path $root 'script/report/build_portal.ps1') -CatalogPath $emptyCatalog -OutputDirectory $failedPortal -MainSnapshotPath (Join-Path $failedDir 'summary.json')|Out-Null
Assert ((Get-Content (Join-Path $failedPortal 'index.html') -Raw -Encoding UTF8).Contains('目前程式檢查未通過')) '最新檢查失敗在首頁清楚顯示'
Write-Host ('UX preview: '+(Join-Path $portal1 'index.html'))
