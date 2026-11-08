#Requires -Version 5.1
$ErrorActionPreference='Stop'
# Real export and archives, using only inert TEMP payloads from the profile test.
. (Join-Path $PSScriptRoot 'driver_profiles_tests.ps1')
. (Join-Path $root 'script/release/driver_release_library.ps1')
$profileReadme=Join-Path $dir 'readme.md'
$original='# Fixture profile' + "`n`n" + '[manifest.json](manifest.json)'
[IO.File]::WriteAllText($profileReadme,$original,[Text.UTF8Encoding]::new($false))
$distribution=Join-Path $temp 'licensed_export'
$null=& (Join-Path $root 'script/package/export_driver_package.ps1') -SourceDirectory $package -OutputDirectory $distribution -ProfileId synthetic_board -ProfilesRoot $registry
$license=Join-Path $distribution 'license'
Assert (Test-Path -LiteralPath $license -PathType Leaf) '獨立驅動包必須隨附自有完整授權本文'
Assert ((Get-FileHash $license).Hash -ceq (Get-FileHash (Join-Path $root 'license')).Hash) '導出授權與主來源逐位元組一致'
Assert (([IO.File]::ReadAllText($profileReadme)) -ceq $original) '導出不修改來源說明的有效連結語境'
foreach($document in @('readme.md','drivers/synthetic_board/readme.md')){
 $path=Join-Path $distribution $document
 $text=[IO.File]::ReadAllText($path)
 foreach($match in [regex]::Matches($text,'\[[^\]]*\]\(([^)]+)\)')){
  $target=$match.Groups[1].Value
  if($target -match '^[a-z]+:|^#'){continue}
  Assert (Test-Path -LiteralPath ([IO.Path]::GetFullPath((Join-Path (Split-Path $path) $target)))) ('導出文件相對連結可解析：'+$document)
 }
}
Assert (([IO.File]::ReadAllText((Join-Path $distribution 'readme.md'))) -match 'Apache-2\.0' -and ([IO.File]::ReadAllText((Join-Path $distribution 'readme.md'))) -match '第三方') '獨立說明區分自有授權與第三方內容'
function LocalAsset([string]$Archive){
 @{Name=[IO.Path]::GetFileName($Archive);Size=(Get-Item $Archive).Length;SHA256=(Get-FileHash $Archive).Hash.ToLowerInvariant();ProfileId='synthetic_board';ManifestSHA256=(Get-FileHash (Join-Path $distribution 'manifest.json')).Hash.ToLowerInvariant()}
}
$good=Join-Path $temp 'licensed.zip';New-DeterministicDriverArchive $distribution $good
Assert-LocalDriverReleaseAsset -Directory $temp -Asset (LocalAsset $good)
Assert $true '實際ZIP發布驗證接受完整授權'
$saved=[IO.File]::ReadAllBytes($license)
foreach($mode in @('missing','tampered')){
 if($mode -eq 'missing'){Remove-Item -LiteralPath $license}else{[IO.File]::WriteAllText($license,'not the approved license')}
 $bad=Join-Path $temp ($mode+'.zip');New-DeterministicDriverArchive $distribution $bad
 Reject {Assert-LocalDriverReleaseAsset -Directory $temp -Asset (LocalAsset $bad)} ('即使重算外層size/hash仍拒絕缺失或篡改授權：'+$mode)
 [IO.File]::WriteAllBytes($license,$saved)
}
foreach($mode in @('wrongcase','duplicate')){
 $bad=Join-Path $temp ($mode+'.zip')
 $base=if($mode -eq 'wrongcase'){Join-Path $temp 'missing.zip'}else{$good}
 Copy-Item -LiteralPath $base -Destination $bad
 $archive=[IO.Compression.ZipFile]::Open($bad,[IO.Compression.ZipArchiveMode]::Update)
 try{$entry=$archive.CreateEntry('LICENSE');$stream=$entry.Open();try{$stream.Write($saved,0,$saved.Length)}finally{$stream.Dispose()}}finally{$archive.Dispose()}
 Reject {Assert-LocalDriverReleaseAsset -Directory $temp -Asset (LocalAsset $bad)} ('Windows解壓不得接受大小寫衝突或重複的授權入口：'+$mode)
}
foreach($name in @('./license','sub/../license','sub\\..\\license','/license','license.','license ','license:stream','core//alias.txt')){
 $bad=Join-Path $temp ([guid]::NewGuid().ToString('N')+'.zip')
 Copy-Item -LiteralPath $good -Destination $bad
 $archive=[IO.Compression.ZipFile]::Open($bad,[IO.Compression.ZipArchiveMode]::Update)
 try{$entry=$archive.CreateEntry($name);$stream=$entry.Open();try{$bytes=[Text.Encoding]::UTF8.GetBytes('not the approved license');$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}}finally{$archive.Dispose()}
 Reject {Assert-LocalDriverReleaseAsset -Directory $temp -Asset (LocalAsset $bad)} ('ZIP不得以Windows路徑別名覆寫已核對檔案：'+$name)
}
foreach($before in @($false,$true)){
 $bad=Join-Path $temp ('prefix_'+$before+'.zip')
 $inputArchive=[IO.Compression.ZipFile]::OpenRead($good)
 $archive=[IO.Compression.ZipFile]::Open($bad,[IO.Compression.ZipArchiveMode]::Create)
 try{
  if($before){$entry=$archive.CreateEntry('license/notice.txt');$s=$entry.Open();$s.Dispose()}
  foreach($originalEntry in $inputArchive.Entries){$entry=$archive.CreateEntry($originalEntry.FullName);$i=$originalEntry.Open();$o=$entry.Open();try{$i.CopyTo($o)}finally{$i.Dispose();$o.Dispose()}}
  if(-not $before){$entry=$archive.CreateEntry('license/notice.txt');$s=$entry.Open();$s.Dispose()}
 }finally{$archive.Dispose();$inputArchive.Dispose()}
 Reject {Assert-LocalDriverReleaseAsset -Directory $temp -Asset (LocalAsset $bad)} ('檔案不得同時作為目錄前綴，與ZIP入口順序無關：'+$before)
}
$extra=Join-Path $temp 'unexpected.zip';Copy-Item -LiteralPath $good -Destination $extra
$archive=[IO.Compression.ZipFile]::Open($extra,[IO.Compression.ZipArchiveMode]::Update)
try{$entry=$archive.CreateEntry('unexpected.txt');$s=$entry.Open();$s.Dispose()}finally{$archive.Dispose()}
Reject {Assert-LocalDriverReleaseAsset -Directory $temp -Asset (LocalAsset $extra)} '正式驅動ZIP不接受manifest與執行結構之外的額外檔案'
$missingRuntime=Join-Path $temp 'missing_runtime.zip';Copy-Item -LiteralPath $good -Destination $missingRuntime
$archive=[IO.Compression.ZipFile]::Open($missingRuntime,[IO.Compression.ZipArchiveMode]::Update)
try{$archive.GetEntry('core/hardware.ps1').Delete()}finally{$archive.Dispose()}
Reject {Assert-LocalDriverReleaseAsset -Directory $temp -Asset (LocalAsset $missingRuntime)} '正式驅動ZIP不可缺必要自有執行檔'
$explicitDirectory=Join-Path $temp 'explicit_directory.zip';Copy-Item -LiteralPath $good -Destination $explicitDirectory
$archive=[IO.Compression.ZipFile]::Open($explicitDirectory,[IO.Compression.ZipArchiveMode]::Update)
try{$entry=$archive.CreateEntry('core/')}finally{$archive.Dispose()}
Assert-LocalDriverReleaseAsset -Directory $temp -Asset (LocalAsset $explicitDirectory)
Assert $true '合法明確目錄入口仍可作為必要檔案的祖先'
[IO.File]::Delete($profileReadme)
$withoutDoc=Join-Path $temp 'without_profile_doc'
$null=& (Join-Path $root 'script/package/export_driver_package.ps1') -SourceDirectory $package -OutputDirectory $withoutDoc -ProfileId synthetic_board -ProfilesRoot $registry
[IO.File]::WriteAllText($profileReadme,$original,[Text.UTF8Encoding]::new($false))
$optional=Join-Path $temp 'optional_doc.zip';New-DeterministicDriverArchive $withoutDoc $optional
Assert-LocalDriverReleaseAsset -Directory $temp -Asset (LocalAsset $optional)
Assert $true '沒有機型README的合法自訂profile仍可獨立分發'
