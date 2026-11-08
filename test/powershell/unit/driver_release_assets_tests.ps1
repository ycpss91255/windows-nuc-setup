#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
function Reject([scriptblock]$Action,[string]$Name){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Assert $failed $Name}
$library=Join-Path $root 'script/release/driver_release_library.ps1'
if(Test-Path -LiteralPath $library){. $library}
Assert ([bool](Get-Command Get-ReleaseDriverAssets -ErrorAction SilentlyContinue)) '可選驅動交付必須提供嚴格版本資產契約'
$temp=Join-Path $env:TEMP ('release_driver_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
$metadata=Join-Path $temp 'metadata.json'
$entry=@{Name='driver_fixture.zip';Size=100;SHA256=('a'*64);ProfileId='fixture';ManifestSHA256=('b'*64)}
function Write-Metadata($Asset=$entry,$Version='v1.0.0'){@{SchemaVersion=1;Releases=@(@{Version=$Version;Assets=@($Asset)})}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $metadata -Encoding UTF8}
Write-Metadata
$assets=@(Get-ReleaseDriverAssets -Path $metadata -Version v1.0.0)
Assert ($assets.Count -eq 1 -and $assets[0].Name -ceq 'driver_fixture.zip') '選定版本取得一個固定資產'
Assert (@(Get-ReleaseDriverAssets -Path $metadata -Version v2.0.0).Count -eq 0) '其他版本不繼承驅動資產'
foreach($mode in @('name','size','hash','profile','manifest','extra')){
 $bad=@{}+$entry
 switch($mode){name{$bad.Name='../outside.zip'}size{$bad.Size=2147483648}hash{$bad.SHA256='bad'}profile{$bad.ProfileId='../bad'}manifest{$bad.ManifestSHA256='bad'}extra{$bad.Unexpected='private'}}
 Write-Metadata $bad
 Reject {Get-ReleaseDriverAssets -Path $metadata -Version v1.0.0} ('錯誤資產拒絕 '+$mode)
}
Write-Metadata
$marker=Get-DriverDraftMarker -Version v1.0.0 -Commit ('c'*40) -MetadataPath $metadata
$draft=@{draft=$true;prerelease=$false;tag_name='v1.0.0';target_commitish=('c'*40);name='v1.0.0';body=$marker;assets=@(@{name=$entry.Name;size=$entry.Size;digest=('sha256:'+$entry.SHA256)})}
Assert-ReleaseDriverDraft -Draft $draft -Version v1.0.0 -Commit ('c'*40) -MetadataPath $metadata -Assets $assets
Assert $true '完整匹配草稿可繼續'
foreach($mode in @('published','tag','commit','body','extra','digest','size','missing')){
 $bad=$draft|ConvertTo-Json -Depth 8|ConvertFrom-Json
 switch($mode){published{$bad.draft=$false}tag{$bad.tag_name='v9.0.0'}commit{$bad.target_commitish='main'}body{$bad.body='foreign draft'}extra{$bad.assets+=@{name='foreign.zip';size=1;digest='bad'}}digest{$bad.assets[0].digest='sha256:'+('0'*64)}size{$bad.assets[0].size=1}missing{$bad.assets=@()}}
 Reject {Assert-ReleaseDriverDraft -Draft $bad -Version v1.0.0 -Commit ('c'*40) -MetadataPath $metadata -Assets $assets} ('拒絕不符草稿 '+$mode)
}
$input=Join-Path $temp 'package';[void][IO.Directory]::CreateDirectory((Join-Path $input 'nested'))
[IO.File]::WriteAllText((Join-Path $input 'manifest.json'),'{"SchemaVersion":2,"Packages":[{"File":"payload.zip"}]}')
[IO.File]::WriteAllText((Join-Path $input 'package.json'),'{"SchemaVersion":2,"ProfileId":"fixture"}')
Copy-Item -LiteralPath (Join-Path $root 'license') -Destination (Join-Path $input 'license')
foreach($name in @('readme.md','install.cmd','payload.zip','core/hardware.ps1','modules/drivers/install_drivers.ps1','modules/drivers/driver_archive_library.ps1','modules/drivers/driver_plan_library.ps1','modules/drivers/driver_installation_library.ps1','modules/updates/update_stage_library.ps1','drivers/fixture/profile.json')){$path=Join-Path $input $name;[void][IO.Directory]::CreateDirectory((Split-Path $path));[IO.File]::WriteAllText($path,'inert fixture data')}
$a=Join-Path $temp 'a.zip';$b=Join-Path $temp 'b.zip'
New-DeterministicDriverArchive -PackageDirectory $input -OutputPath $a
(Get-Item (Join-Path $input 'readme.md')).LastWriteTime=Get-Date
New-DeterministicDriverArchive -PackageDirectory $input -OutputPath $b
Assert ((Get-FileHash $a).Hash -ceq (Get-FileHash $b).Hash) '固定時間與排序產生相同 ZIP 位元'
Reject {New-DeterministicDriverArchive -PackageDirectory $input -OutputPath $a} '封存不覆寫'
$local=@{Name='a.zip';Size=(Get-Item $a).Length;SHA256=(Get-FileHash $a).Hash.ToLowerInvariant();ProfileId='fixture';ManifestSHA256=(Get-FileHash (Join-Path $input 'manifest.json')).Hash.ToLowerInvariant()}
Assert-LocalDriverReleaseAsset -Directory $temp -Asset $local
Assert $true 'ZIP 身分與 manifest hash 一致'
$local.ManifestSHA256='0'*64
Reject {Assert-LocalDriverReleaseAsset -Directory $temp -Asset $local} 'ZIP manifest 不符拒絕'
Write-Host 'ALL PASS: driver release assets; TEMP only, no remote calls'
