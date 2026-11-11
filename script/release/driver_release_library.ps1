#Requires -Version 5.1
# Maintainer-only release helpers. Dot-sourcing does not perform remote writes.
function Assert-DriverReleaseFields($Value,[string[]]$Fields){
 if($null -eq $Value -or @($Value.PSObject.Properties.Name|Where-Object {$_ -cnotin $Fields}).Count -or @($Fields|Where-Object {$_ -cnotin $Value.PSObject.Properties.Name}).Count){throw 'Driver release metadata fields mismatch.'}
}
function Get-ReleaseDriverAssets {
 param([string]$Path,[string]$Version)
 $metadata=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json
 Assert-DriverReleaseFields $metadata @('SchemaVersion','Releases')
 if($metadata.SchemaVersion -ne 1 -or $metadata.Releases -isnot [array]){throw 'Invalid driver release metadata schema.'}
 $versions=@{};$names=@{};$result=@()
 foreach($release in $metadata.Releases){
  Assert-DriverReleaseFields $release @('Version','Assets')
  if($release.Version -cnotmatch '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-rc[1-9][0-9]*)?$' -or $versions.ContainsKey($release.Version) -or $release.Assets -isnot [array]){throw 'Invalid or duplicate driver release version.'}
  $versions[$release.Version]=$true;$names=@{}
  foreach($asset in $release.Assets){
   Assert-DriverReleaseFields $asset @('Name','Size','SHA256','ProfileId','ManifestSHA256')
   if($asset.Name -cnotmatch '^[a-z0-9][a-z0-9_\.]*\.zip$' -or $asset.Name.Contains('..') -or $names.ContainsKey($asset.Name) -or ($asset.Size -isnot [long] -and $asset.Size -isnot [int]) -or $asset.Size -le 0 -or $asset.Size -ge 2147483648 -or $asset.SHA256 -cnotmatch '^[a-f0-9]{64}$' -or $asset.ManifestSHA256 -cnotmatch '^[a-f0-9]{64}$' -or $asset.ProfileId -cnotmatch '^[a-z0-9]+(?:_[a-z0-9]+)*$'){throw 'Invalid driver release asset.'}
   $names[$asset.Name]=$true
   if($release.Version -ceq $Version){$result+=@($asset)}
  }
 }
 return $result
}
function Get-DriverDraftMarker {
 param([string]$Version,[string]$Commit,[string]$MetadataPath)
 if($Commit -cnotmatch '^[a-f0-9]{40}$'){throw 'Invalid staging commit.'}
 return ('<!-- windows_setup_driver_stage_v1 '+$Version+' '+$Commit+' '+(Get-FileHash -LiteralPath $MetadataPath -Algorithm SHA256).Hash.ToLowerInvariant()+' -->')
}
function Assert-ReleaseDraftRecord {
 param($Value,[string]$Version,$ExpectedId)
 if($Value -isnot [pscustomobject] -or ($Value.id -isnot [int] -and $Value.id -isnot [long]) -or $Value.id -le 0 -or $Value.id -ne $ExpectedId -or $Value.tag_name -isnot [string] -or $Value.tag_name -cne $Version -or $Value.draft -isnot [bool] -or $Value.draft -cne $true -or $Value.immutable -isnot [bool] -or $Value.immutable -cne $false){throw 'Selected release ID is foreign, changed or not an editable draft.'}
}
function Get-ReleaseDraftByTag {
 param([ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$Repository,[ValidatePattern('^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-rc[1-9][0-9]*)?$')][string]$Version,$ExpectedId)
 if($PSBoundParameters.ContainsKey('ExpectedId')){
  if(($ExpectedId -isnot [int] -and $ExpectedId -isnot [long]) -or $ExpectedId -le 0){throw 'Expected draft ID must be a positive integer.'}
  $selectedId=[long]$ExpectedId
 }else{
  $rows=@(& gh api --paginate ('repos/'+$Repository+'/releases?per_page=100') --jq '.[] | {id,tag_name,draft,immutable} | @json')
  if($LASTEXITCODE -ne 0){throw 'Cannot list release drafts; no fallback or overwrite.'}
  $matches=@()
  foreach($line in $rows){
   if($line -isnot [string] -or -not $line.Trim().StartsWith('{')){throw 'Release list must contain JSON object rows.'}
   $row=ConvertFrom-Json -InputObject $line
   if($row -isnot [pscustomobject] -or ($row.id -isnot [int] -and $row.id -isnot [long]) -or $row.id -le 0 -or $row.tag_name -isnot [string] -or $row.draft -isnot [bool] -or $row.immutable -isnot [bool]){throw 'Release list row has invalid typed identity.'}
   if($row.tag_name -ceq $Version){$matches+=@($row)}
  }
  if($matches.Count -ne 1){throw 'Release tag must identify exactly one listed draft.'}
  Assert-ReleaseDraftRecord -Value $matches[0] -Version $Version -ExpectedId $matches[0].id
  $selectedId=[long]$matches[0].id
 }
 # ASCII transport preserves UTF-8 notes under native PS5 console code pages.
 $encoded=@(& gh api ('repos/'+$Repository+'/releases/'+$selectedId) --jq 'tojson | @base64')
 if($LASTEXITCODE -ne 0 -or $encoded.Count -ne 1 -or $encoded[0] -isnot [string]){throw 'Cannot read the selected draft ID.'}
 $json=[Text.UTF8Encoding]::new($false,$true).GetString([Convert]::FromBase64String($encoded[0]))
 if(-not $json.Trim().StartsWith('{')){throw 'Release ID response must be a JSON object.'}
 $draft=ConvertFrom-Json -InputObject $json
 Assert-ReleaseDraftRecord -Value $draft -Version $Version -ExpectedId $selectedId
 return $draft
}
function Assert-ReleaseAssetSet {
 param($Actual,[object[]]$Expected)
 if(@($Actual).Count -ne $Expected.Count){throw 'Release asset count mismatch.'}
 foreach($item in $Expected){$matches=@($Actual|Where-Object name -ceq $item.Name);if($matches.Count -ne 1 -or $matches[0].digest -cne ('sha256:'+$item.SHA256) -or ($null -ne $item.Size -and $matches[0].size -ne $item.Size)){throw 'Release asset digest or size mismatch.'}}
}
function Assert-ReleaseDriverDraft {
 param($Draft,[string]$Version,[string]$Commit,[string]$MetadataPath,[object[]]$Assets)
 if($Draft.prerelease -isnot [bool] -or $Draft.prerelease -cne [bool]($Version -cmatch '-rc[1-9][0-9]*$') -or $Draft.draft -isnot [bool] -or $Draft.draft -cne $true -or $Draft.tag_name -cne $Version -or $Draft.target_commitish -cne $Commit -or $Draft.name -cne $Version -or $Draft.body -cne (Get-DriverDraftMarker $Version $Commit $MetadataPath)){throw 'Foreign or mismatched driver staging draft.'}
 Assert-ReleaseAssetSet -Actual $Draft.assets -Expected $Assets
}
function Assert-LocalDriverReleaseAsset {
 param([string]$Directory,$Asset)
 $file=Join-Path $Directory $Asset.Name
 if(-not(Test-Path -LiteralPath $file -PathType Leaf) -or (Get-Item -LiteralPath $file).Attributes -band [IO.FileAttributes]::ReparsePoint -or (Get-Item -LiteralPath $file).Length -ne $Asset.Size -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant() -cne $Asset.SHA256){throw 'Local driver release asset mismatch.'}
 Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
 $archive=[IO.Compression.ZipFile]::OpenRead($file)
 try{
  $names=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $files=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  $directories=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
  foreach($entry in $archive.Entries){
   $name=$entry.FullName
   if($name.Contains('\') -or $name.StartsWith('/')){throw 'Driver archive contains a noncanonical Windows path.'}
   $isDirectory=$name.EndsWith('/')
   if($isDirectory){$name=$name.Substring(0,$name.Length-1)}
   $segments=@($name.Split('/'))
   if(@($segments|Where-Object {[string]::IsNullOrEmpty($_) -or $_ -in @('.','..') -or $_.EndsWith('.') -or $_.EndsWith(' ') -or $_.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0}).Count -or -not $names.Add($name)){throw 'Driver archive contains an aliased or duplicate Windows path.'}
   for($index=1;$index -lt $segments.Count;$index++){
    $parent=$segments[0..($index-1)] -join '/'
    if($files.Contains($parent)){throw 'Driver archive uses a file as a directory.'}
    [void]$directories.Add($parent)
   }
   if($isDirectory){if($files.Contains($name)){throw 'Driver archive uses a file as a directory.'};[void]$directories.Add($name)}
   else{if($directories.Contains($name)){throw 'Driver archive uses a directory as a file.'};[void]$files.Add($name)}
  }
  $licenses=@($archive.Entries|Where-Object FullName -ieq 'license')
  if($licenses.Count -ne 1 -or $licenses[0].FullName -cne 'license' -or $licenses[0].Length -ne 11358){throw 'Driver archive must contain exactly one canonical root license.'}
  $licenseStream=$licenses[0].Open();$licenseSHA=[Security.Cryptography.SHA256]::Create()
  try{$licenseHash=([BitConverter]::ToString($licenseSHA.ComputeHash($licenseStream))).Replace('-','').ToLowerInvariant()}finally{$licenseStream.Dispose();$licenseSHA.Dispose()}
  if($licenseHash -cne 'cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30'){throw 'Driver archive own-code Apache-2.0 license is missing or modified.'}
  foreach($name in @('manifest.json','package.json')){
   $entries=@($archive.Entries|Where-Object FullName -ceq $name)
   if($entries.Count -ne 1 -or $entries[0].Length -gt 10485760){throw 'Driver archive identity entry missing or oversized.'}
   $stream=$entries[0].Open();$memory=[IO.MemoryStream]::new()
   try{$stream.CopyTo($memory);$bytes=$memory.ToArray()}finally{$stream.Dispose();$memory.Dispose()}
   if($name -ceq 'manifest.json'){$sha=[Security.Cryptography.SHA256]::Create();try{$hash=([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()};if($hash -cne $Asset.ManifestSHA256){throw 'Driver manifest digest mismatch.'};$payloadManifest=[Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF)|ConvertFrom-Json}
   else{$identity=[Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF)|ConvertFrom-Json;if($identity.SchemaVersion -ne 2 -or $identity.ProfileId -cne $Asset.ProfileId){throw 'Driver archive profile mismatch.'}}
  }
  $expected=@('manifest.json','package.json','license','readme.md','install.cmd','core/hardware.ps1','modules/drivers/install_drivers.ps1','modules/drivers/driver_archive_library.ps1','modules/drivers/driver_plan_library.ps1','modules/drivers/driver_installation_library.ps1','modules/updates/update_stage_library.ps1',('drivers/'+$Asset.ProfileId+'/profile.json'))
  if($payloadManifest.SchemaVersion -ne 2 -or -not @($payloadManifest.Packages).Count){throw 'Driver archive must declare its payload files.'}
  foreach($payload in $payloadManifest.Packages){if($payload.File -isnot [string] -or $payload.File -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*\.zip$' -or $payload.File.Contains('..') -or $payload.File -in $expected){throw 'Driver archive payload name is invalid or duplicated.'};$expected+=@($payload.File)}
  $profileReadme='drivers/'+$Asset.ProfileId+'/readme.md'
  if(@($archive.Entries|Where-Object FullName -ceq $profileReadme).Count){$expected+=@($profileReadme)}
  $actual=@($archive.Entries|Where-Object {-not $_.FullName.EndsWith('/')}|ForEach-Object {$_.FullName})
  if($actual.Count -ne $expected.Count -or @($expected|Where-Object {$_ -cnotin $actual}).Count){throw 'Driver archive file set does not match its self-contained distribution.'}
  foreach($directoryName in @($archive.Entries|Where-Object {$_.FullName.EndsWith('/')}|ForEach-Object {$_.FullName})){
   if(-not @($expected|Where-Object {$_.StartsWith($directoryName,[StringComparison]::Ordinal)}).Count){throw 'Driver archive contains an unexpected directory.'}
  }
 }finally{$archive.Dispose()}
}
function New-DeterministicDriverArchive {
 param([string]$PackageDirectory,[string]$OutputPath)
 $source=[IO.Path]::GetFullPath((Resolve-Path -LiteralPath $PackageDirectory).Path).TrimEnd('\','/');$output=[IO.Path]::GetFullPath($OutputPath)
 if($output.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase) -or (Test-Path -LiteralPath $output)){throw 'Archive output must be new and outside package.'}
 $items=@(Get-ChildItem -LiteralPath $source -Recurse -Force)
 if((Get-Item -LiteralPath $source).Attributes -band [IO.FileAttributes]::ReparsePoint -or @($items|Where-Object {$_.Attributes -band [IO.FileAttributes]::ReparsePoint}).Count){throw 'Driver package cannot contain reparse points.'}
 $files=@($items|Where-Object {-not $_.PSIsContainer});$relative=@($files|ForEach-Object {$_.FullName.Substring($source.Length+1).Replace('\','/')})
 [Array]::Sort($relative,[StringComparer]::Ordinal)
 Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
 $stream=[IO.File]::Open($output,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
 $zip=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Create,$false)
 try{foreach($name in $relative){$entry=$zip.CreateEntry($name,[IO.Compression.CompressionLevel]::NoCompression);$entry.LastWriteTime=[DateTimeOffset]::new(2000,1,1,0,0,0,[TimeSpan]::Zero);$input=[IO.File]::OpenRead((Join-Path $source $name));$destination=$entry.Open();try{$input.CopyTo($destination)}finally{$destination.Dispose();$input.Dispose()}}}finally{$zip.Dispose();$stream.Dispose()}
}
function Invoke-StageDriverRelease {
 param([string]$Version,[ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')][string]$Repository,[string]$PackageRoot,[string]$AssetDirectory,[string]$MetadataPath)
 $assets=@(Get-ReleaseDriverAssets $MetadataPath $Version)
 if(-not $assets.Count){throw 'No declared driver assets for this version.'}
 $commit=& git -C $PackageRoot rev-parse ($Version+'^{commit}')
 if($LASTEXITCODE -ne 0 -or $commit -cnotmatch '^[a-f0-9]{40}$'){throw 'Release tag does not resolve to one commit.'}
 & git -C $PackageRoot merge-base --is-ancestor $commit refs/remotes/origin/main
 if($LASTEXITCODE -ne 0){throw 'Driver release source is not in main history.'}
 $remote=& gh api ('repos/'+$Repository+'/commits/'+$Version) --jq '.sha'
 if($LASTEXITCODE -ne 0 -or $remote -cne $commit){throw 'Remote tag commit mismatch.'}
 foreach($asset in $assets){Assert-LocalDriverReleaseAsset -Directory $AssetDirectory -Asset $asset}
 $existing=& gh api --paginate ('repos/'+$Repository+'/releases?per_page=100') --jq '.[].tag_name'
 if($LASTEXITCODE -ne 0 -or $existing -ccontains $Version){throw 'Existing release or unavailable release list; never overwrite.'}
 $marker=Get-DriverDraftMarker $Version $commit $MetadataPath
 $notes=Join-Path ([IO.Path]::GetTempPath()) ('driver_stage_'+[guid]::NewGuid().ToString('N')+'.md')
 [IO.File]::WriteAllText($notes,$marker,[Text.UTF8Encoding]::new($false))
 try{
  $arguments=@('release','create',$Version,'--repo',$Repository,'--verify-tag','--target',$commit,'--draft','--title',$Version,'--notes-file',$notes)
  if($Version -cmatch '-rc[1-9][0-9]*$'){$arguments+=@('--prerelease','--latest=false')}
  $arguments+=@($assets|ForEach-Object {Join-Path $AssetDirectory $_.Name})
  & gh @arguments
  if($LASTEXITCODE -ne 0){throw 'Driver draft staging failed; no publication or automatic overwrite.'}
 }finally{Remove-Item -LiteralPath $notes -Force -ErrorAction SilentlyContinue}
 $draft=Get-ReleaseDraftByTag -Repository $Repository -Version $Version
 Assert-ReleaseDriverDraft $draft $Version $commit $MetadataPath $assets
 Write-Host 'Driver draft verified; tag CI must attach complete quality evidence before publication.'
}
