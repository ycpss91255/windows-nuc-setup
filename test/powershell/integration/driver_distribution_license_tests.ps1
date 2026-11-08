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
