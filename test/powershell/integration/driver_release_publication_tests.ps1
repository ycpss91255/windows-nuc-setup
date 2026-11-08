#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
$publisher=Join-Path $root 'script/report/publish_quality_release.ps1'
Assert ((Get-Command $publisher).Parameters.ContainsKey('DriverAssetManifestPath')) '品質發布須支援嚴格獨立驅動資產契約'
# Reuse the existing real 80% coverage CLI fixture and its full no-driver regressions.
. (Join-Path $PSScriptRoot 'repo_publication_tests.ps1')
. (Join-Path $root 'script/release/driver_release_library.ps1')
$driverMetadata=Join-Path $fixture 'driver_assets.json'
$driverAsset=@{Name='driver_fixture.zip';Size=100;SHA256=('d'*64);ProfileId='fixture';ManifestSHA256=('e'*64)}
@{SchemaVersion=1;Releases=@(@{Version='v1.0.0';Assets=@($driverAsset)})}|ConvertTo-Json -Depth 8|Set-Content $driverMetadata -Encoding UTF8
$script:marker=Get-DriverDraftMarker v1.0.0 $identity.Commit $driverMetadata
function gh {
 $words=@($args);$global:LASTEXITCODE=0
 if($words[0] -eq 'api' -and $words -contains '--paginate'){if($script:driverMode -ne 'missing-draft'){return 'v1.0.0'};return}
 if($words[0] -eq 'api' -and $words[1] -like '*/commits/*'){if($script:driverMode -eq 'wrong-tag'){return ('f'*40)};return $identity.Commit}
 if($words[0] -eq 'release' -and $words[1] -eq 'create'){throw 'Driver publication must never create an empty driver release.'}
 if($words[0] -eq 'release' -and $words[1] -eq 'upload'){
  Assert ($words -cnotcontains '--clobber') '附加品質證據不覆寫'
  $script:uploaded++
  foreach($word in $words|Select-Object -Skip 3){if(Test-Path -LiteralPath ([string]$word) -PathType Leaf){$script:remoteAssets+=@(@{name=[IO.Path]::GetFileName($word);size=(Get-Item -LiteralPath $word).Length;digest=('sha256:'+(Get-FileHash -LiteralPath $word).Hash.ToLowerInvariant())})}}
  if($script:driverMode -eq 'partial-upload'){$script:remoteAssets=@($script:remoteAssets|Select-Object -Skip 1)}
  return
 }
 if($words[0] -eq 'release' -and $words[1] -eq 'edit'){if($words -contains '--draft=false'){$script:published++};return}
 if($words[0] -eq 'api' -and $words[1] -like '*/releases/tags/*'){
  if($script:published){return (@{immutable=$true;draft=$false;tag_name='v1.0.0';assets=$script:remoteAssets;html_url='https://github.com/example/repo/releases/tag/v1.0.0'}|ConvertTo-Json -Depth 8)}
  $draft=@{draft=$true;tag_name='v1.0.0';target_commitish=$identity.Commit;name='v1.0.0';body=$script:marker;assets=$script:remoteAssets}
  switch($script:driverMode){published{$draft.draft=$false}foreign{$draft.body='other draft'}wrong-commit{$draft.target_commitish='main'}}
  return ($draft|ConvertTo-Json -Depth 8)
 }
 throw ('Unexpected driver publication call: '+($words -join ' '))
}
foreach($mode in @('success','missing-draft','published','foreign','wrong-commit','wrong-tag','extra','bad-digest','partial-upload')){
 $script:driverMode=$mode;$script:published=0;$script:uploaded=0
 $script:remoteAssets=@(@{name=$driverAsset.Name;size=$driverAsset.Size;digest=('sha256:'+$driverAsset.SHA256)})
 if($mode -eq 'extra'){$script:remoteAssets+=@{name='foreign.zip';size=1;digest='sha256:'+('f'*64)}}
 if($mode -eq 'bad-digest'){$script:remoteAssets[0].digest='sha256:'+('f'*64)}
 $accepted=$true;try{& $publisher -PublicDirectory $public -Version v1.0.0 -Commit $identity.Commit -NotesPath (Join-Path $public 'summary.md') -Repository example/repo -CoverageToolPath $tool -DriverAssetManifestPath $driverMetadata|Out-Null}catch{$accepted=$false}
 Assert ($accepted -eq ($mode -eq 'success')) ('驅動品質全集發布結果 '+$mode)
 Assert ($script:published -eq $(if($mode -eq 'success'){1}else{0})) ('錯誤草稿不發布 '+$mode)
 if($mode -notin @('success','partial-upload')){Assert ($script:uploaded -eq 0) ('核對失敗不改草稿 '+$mode)}
}
Remove-Item Function:\gh
Write-Host 'ALL PASS: driver-aware publication; mocked GitHub, no network writes'
