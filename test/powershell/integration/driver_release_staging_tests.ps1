#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/release/driver_release_library.ps1')
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
function Reject([scriptblock]$Action,[string]$Name){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Assert $failed $Name}
Assert ([bool](Get-Command Invoke-StageDriverRelease -ErrorAction SilentlyContinue)) '正式草稿入口須先核對來源與資產再上傳'
$temp=Join-Path $env:TEMP ('driver_stage_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
$package=Join-Path $temp 'package';[void][IO.Directory]::CreateDirectory($package)
[IO.File]::WriteAllText((Join-Path $package 'manifest.json'),'{"SchemaVersion":2,"Packages":[{"File":"payload.zip"}]}')
[IO.File]::WriteAllText((Join-Path $package 'package.json'),'{"SchemaVersion":2,"ProfileId":"fixture"}')
Copy-Item -LiteralPath (Join-Path $root 'license') -Destination (Join-Path $package 'license')
foreach($name in @('readme.md','install.cmd','payload.zip','core/hardware.ps1','modules/drivers/install_drivers.ps1','modules/drivers/driver_archive_library.ps1','modules/drivers/driver_plan_library.ps1','modules/drivers/driver_installation_library.ps1','modules/updates/update_stage_library.ps1','drivers/fixture/profile.json')){$path=Join-Path $package $name;[void][IO.Directory]::CreateDirectory((Split-Path $path));[IO.File]::WriteAllText($path,'inert fixture data')}
$zip=Join-Path $temp 'driver_fixture.zip';New-DeterministicDriverArchive $package $zip
$metadata=Join-Path $temp 'assets.json';$asset=@{Name='driver_fixture.zip';Size=(Get-Item $zip).Length;SHA256=(Get-FileHash $zip).Hash.ToLowerInvariant();ProfileId='fixture';ManifestSHA256=(Get-FileHash (Join-Path $package 'manifest.json')).Hash.ToLowerInvariant()}
@{SchemaVersion=1;Releases=@(@{Version='v1.0.0';Assets=@($asset)})}|ConvertTo-Json -Depth 8|Set-Content $metadata -Encoding UTF8
$global:releaseStageMode='success';$global:releaseStageCreated=0;$global:releaseStageMarker=Get-DriverDraftMarker v1.0.0 ('a'*40) $metadata
function git { $words=@($args);$global:LASTEXITCODE=0;if($words -contains 'rev-parse'){return ('a'*40)};if($words -contains 'merge-base'){if($global:releaseStageMode -eq 'not-main'){$global:LASTEXITCODE=1};return};throw 'unexpected git' }
function gh {
 $words=@($args);$global:LASTEXITCODE=0
 if($words[0] -eq 'api' -and $words -contains '--paginate'){
  if(($words -join ' ') -match '@json'){return (@{id=42;draft=$true;immutable=$false;tag_name='v1.0.0'}|ConvertTo-Json -Compress)}
  if($global:releaseStageMode -eq 'existing'){return 'v1.0.0'};return
 }
 if($words[0] -eq 'api' -and $words[1] -like '*/commits/*'){if($global:releaseStageMode -eq 'wrong-tag'){return ('b'*40)};return ('a'*40)}
 if($words[0] -eq 'release' -and $words[1] -eq 'create'){$global:releaseStageCreated++;Assert ($words -contains '--draft' -and $words -contains '--verify-tag' -and $words -contains '--target' -and $words -contains $zip -and $words -cnotcontains '--clobber') '只建立新草稿且固定tag與資產';return}
 if($words[0] -eq 'api' -and $words[1] -like '*/releases/tags/*'){$global:LASTEXITCODE=1;return}
 if($words[0] -eq 'api' -and $words[1] -eq 'repos/example/repo/releases/42'){
  $data=@{id=42;immutable=$false;draft=$true;prerelease=$false;tag_name='v1.0.0';target_commitish=('a'*40);name='v1.0.0';body=$global:releaseStageMarker;assets=@(@{name=$asset.Name;size=$asset.Size;digest=('sha256:'+$asset.SHA256)})}|ConvertTo-Json -Depth 8 -Compress
  return [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($data))
 }
 throw ('unexpected gh '+($words -join ' '))
}
$arguments=@{Version='v1.0.0';Repository='example/repo';PackageRoot=$root;AssetDirectory=$temp;MetadataPath=$metadata}
Invoke-StageDriverRelease @arguments
Assert ($global:releaseStageCreated -eq 1) '標籤main資產全部匹配才建立草稿'
foreach($mode in @('not-main','wrong-tag','existing')){$global:releaseStageMode=$mode;$before=$global:releaseStageCreated;Reject {Invoke-StageDriverRelease @arguments} ('拒絕 '+$mode);Assert ($global:releaseStageCreated -eq $before) ('失敗不建立草稿 '+$mode)}
$global:releaseStageMode='success'
& (Join-Path $root 'script/release/stage_driver_release.ps1') -Version v1.0.0 -Repository example/repo -AssetDirectory $temp -MetadataPath $metadata
Assert ($global:releaseStageCreated -eq 2) '正式薄入口動態取得repo根且保留同一草稿驗證'
Remove-Item Function:\git,Function:\gh
Write-Host 'ALL PASS: release staging; TEMP and mocked remote only'
