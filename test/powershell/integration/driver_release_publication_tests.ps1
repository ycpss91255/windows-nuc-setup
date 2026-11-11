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
$global:driverReleaseMarker=Get-DriverDraftMarker v1.0.0 $identity.Commit $driverMetadata
function gh {
 $words=@($args);$global:LASTEXITCODE=0
 if($words[0] -eq 'api' -and $words -contains '--paginate'){
  if($global:driverReleaseMode -eq 'missing-draft'){return}
  if(($words -join ' ') -match '@json'){
   @{id=42;tag_name='v1.0.0';draft=$true;immutable=$false}|ConvertTo-Json -Compress
   if($global:driverReleaseMode -eq 'duplicate'){@{id=43;tag_name='v1.0.0';draft=$true;immutable=$false}|ConvertTo-Json -Compress};return
  }
  return 'v1.0.0'
 }
 if($words[0] -eq 'api' -and $words[1] -like '*/commits/*'){if($global:driverReleaseMode -eq 'wrong-tag'){return ('f'*40)};return $identity.Commit}
 if($words[0] -eq 'release' -and $words[1] -eq 'create'){throw 'Driver publication must never create an empty driver release.'}
 if($words[0] -eq 'api' -and $words[1] -like 'https://uploads.github.com/repos/example/repo/releases/42/assets?name=*'){
  Assert ($words -cnotcontains '--clobber' -and $words -contains '--input' -and $words[[Array]::IndexOf($words,'--method')+1] -ceq 'POST') '品質資產只 POST 固定官方 host/repo/ID 且不覆寫'
  $global:driverReleaseUploaded++
  $word=$words[[Array]::IndexOf($words,'--input')+1]
  Assert (([uri]$words[1]).Query -ceq ('?name='+[uri]::EscapeDataString([IO.Path]::GetFileName($word)))) '資產 basename 以 URI encode 寫入 query'
  $global:driverReleaseRemoteAssets+=@(@{name=[IO.Path]::GetFileName($word);size=(Get-Item -LiteralPath $word).Length;digest=('sha256:'+(Get-FileHash -LiteralPath $word).Hash.ToLowerInvariant())})
  if($global:driverReleaseMode -eq 'partial-upload' -and $global:driverReleaseUploaded -eq 1){$global:driverReleaseRemoteAssets=@($global:driverReleaseRemoteAssets|Select-Object -Skip 1)}
  return '{}'
 }
 if($words[0] -eq 'api' -and $words[1] -eq 'repos/example/repo/releases/42' -and $words -contains '--method'){
  $bytes=[IO.File]::ReadAllBytes($words[[Array]::IndexOf($words,'--input')+1]);$payload=[Text.UTF8Encoding]::new($false,$true).GetString($bytes)|ConvertFrom-Json
  Assert ($words[[Array]::IndexOf($words,'--method')+1] -ceq 'PATCH') '只 PATCH 既有已選定 ID'
  if($payload.PSObject.Properties['draft']){
   Assert ($payload.draft -is [bool] -and $payload.draft -ceq $false -and $global:driverReleaseNotesApplied -and $global:driverReleaseRemoteAssets.Count -eq 13) '十三個資產及 notes 核對完成後才發布 JSON false'
   $global:driverReleasePublished++
  }else{
   Assert ($payload.name -ceq 'v1.0.0' -and $payload.body -ceq [IO.File]::ReadAllText((Join-Path $public 'summary.md'))) 'stage marker 最後才被精確中文正式 notes 取代'
   $global:driverReleaseNotes=$payload.body;$global:driverReleaseNotesApplied=$true
  };return '{}'
 }
 if($words[0] -eq 'api' -and $words[1] -eq 'repos/example/repo/releases/42'){
  $global:driverReleaseReadCount++
  $draft=@{id=42;immutable=$false;draft=$true;prerelease=$false;tag_name='v1.0.0';target_commitish=$identity.Commit;name='v1.0.0';body=$(if($global:driverReleaseNotesApplied){$global:driverReleaseNotes}else{$global:driverReleaseMarker});assets=$global:driverReleaseRemoteAssets;upload_url='https://untrusted.invalid/must_not_receive_credentials'}
  switch($global:driverReleaseMode){published{$draft.draft=$false}foreign{$draft.body='other draft'}wrong-commit{$draft.target_commitish='main'}changed-id{$draft.id=43}immutable{$draft.immutable=$true}changed-after-upload{if($global:driverReleaseReadCount -ge 2){$draft.id=43}}wrong-notes{if($global:driverReleaseNotesApplied){$draft.body='altered notes'}}}
  return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($draft|ConvertTo-Json -Depth 8 -Compress)))
 }
 if($words[0] -eq 'api' -and $words[1] -like '*/releases/tags/*'){
  if($global:driverReleasePublished){return (@{id=42;immutable=$true;draft=$false;tag_name='v1.0.0';assets=$global:driverReleaseRemoteAssets;html_url='https://github.com/example/repo/releases/tag/v1.0.0'}|ConvertTo-Json -Depth 8)}
  $global:LASTEXITCODE=1;return
 }
 throw ('Unexpected driver publication call: '+($words -join ' '))
}
foreach($mode in @('success','missing-draft','published','foreign','wrong-commit','wrong-tag','extra','bad-digest','partial-upload','duplicate','changed-id','immutable','changed-after-upload','wrong-notes')){
 $global:driverReleaseMode=$mode;$global:driverReleasePublished=0;$global:driverReleaseUploaded=0;$global:driverReleaseReadCount=0;$global:driverReleaseNotesApplied=$false
 $global:driverReleaseRemoteAssets=@(@{name=$driverAsset.Name;size=$driverAsset.Size;digest=('sha256:'+$driverAsset.SHA256)})
 if($mode -eq 'extra'){$global:driverReleaseRemoteAssets+=@{name='foreign.zip';size=1;digest='sha256:'+('f'*64)}}
 if($mode -eq 'bad-digest'){$global:driverReleaseRemoteAssets[0].digest='sha256:'+('f'*64)}
 $accepted=$true;try{& $publisher -PublicDirectory $public -Version v1.0.0 -Commit $identity.Commit -NotesPath (Join-Path $public 'summary.md') -Repository example/repo -CoverageToolPath $tool -DriverAssetManifestPath $driverMetadata|Out-Null}catch{$accepted=$false;Write-Host ('Fixture publisher error: '+$_.Exception.Message)}
 Assert ($accepted -eq ($mode -eq 'success')) ('驅動品質全集發布結果 '+$mode)
 Assert ($global:driverReleasePublished -eq $(if($mode -eq 'success'){1}else{0})) ('錯誤草稿不發布 '+$mode)
 if($mode -notin @('success','partial-upload','changed-after-upload','wrong-notes')){Assert ($global:driverReleaseUploaded -eq 0) ('核對失敗不改草稿 '+$mode)}
}
Remove-Item Function:\gh
Write-Host 'ALL PASS: driver-aware publication; mocked GitHub, no network writes'
