#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$library=Join-Path $root 'modules\init\provisioning_asset_library.ps1'
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++}
Assert (Test-Path -LiteralPath $library) 'read-only provisioning asset validator exists'
. $library
$temp=Join-Path ([IO.Path]::GetTempPath()) ('init_asset_validation_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp|Out-Null
$xml=Get-InitProvisioningSourceXml
[IO.File]::WriteAllText((Join-Path $temp 'hide_oobe.xml'),$xml,(New-Object Text.UTF8Encoding($false)))
[IO.File]::WriteAllText((Join-Path $temp 'hide_oobe.ppkg'),'synthetic package; never install')
$manifest=New-InitProvisioningProvenance -SourcePath (Join-Path $temp 'hide_oobe.xml') -PackagePath (Join-Path $temp 'hide_oobe.ppkg')
function WriteManifest {[IO.File]::WriteAllText((Join-Path $temp 'provenance.json'),($manifest|ConvertTo-Json -Depth 4))}
WriteManifest
$script:metadataCalls=0;$script:badMetadata=$false;$script:missingMetadata=$false
function Get-ProvisioningPackage {param($PackagePath,$LogsDirectoryPath,$ErrorAction) $script:metadataCalls++;if($script:missingMetadata){throw (New-Object Management.Automation.CommandNotFoundException('Get-ProvisioningPackage unavailable'))};[pscustomobject]@{PackageID='1c2605ea-96ae-42fc-8f11-45fc0cb9d133';PackageName=$(if($script:badMetadata){'other'}else{'windows_setup_hide_oobe'});Version='1.0';Rank=0;OwnerType=5000}}
Assert ([bool](Get-Command Assert-InitProvisioningAssetSource -ErrorAction SilentlyContinue)) 'source verification is independent of Windows client provisioning API'
$sourceResult=Assert-InitProvisioningAssetSource $temp
Assert ($sourceResult.PackageSHA256 -eq $manifest.PackageSHA256 -and $script:metadataCalls -eq 0) 'pure source check never claims or invokes native metadata'
$result=Assert-InitProvisioningAsset -AssetRoot $temp
Assert ($result.PackageSHA256 -eq $manifest.PackageSHA256 -and $script:metadataCalls -eq 1) 'source and package hashes precede read-only metadata validation'
[IO.File]::AppendAllText((Join-Path $temp 'hide_oobe.ppkg'),'tampered')
$failed=$false;try{Assert-InitProvisioningAsset $temp}catch{$failed=$true}
Assert ($failed -and $script:metadataCalls -eq 1) 'tampered package rejected before metadata command'
[IO.File]::WriteAllText((Join-Path $temp 'hide_oobe.ppkg'),'synthetic package; never install')
$badXml=$xml.Replace('</Desktop>','<Other>True</Other></Desktop>')
[IO.File]::WriteAllText((Join-Path $temp 'hide_oobe.xml'),$badXml,(New-Object Text.UTF8Encoding($false)))
$manifest.SourceSHA256=(Get-FileHash (Join-Path $temp 'hide_oobe.xml')).Hash;WriteManifest
$failed=$false;try{Assert-InitProvisioningAsset $temp}catch{$failed=$true}
Assert ($failed -and $script:metadataCalls -eq 1) 'extra setting rejected even when source hash is updated'
[IO.File]::WriteAllText((Join-Path $temp 'hide_oobe.xml'),$xml,(New-Object Text.UTF8Encoding($false)))
$manifest.SourceSHA256=(Get-FileHash (Join-Path $temp 'hide_oobe.xml')).Hash;WriteManifest
$script:badMetadata=$true
$failed=$false;try{Assert-InitProvisioningAsset $temp}catch{$failed=$true}
Assert $failed 'package metadata identity mismatch is rejected'
$script:badMetadata=$false
$script:missingMetadata=$true
$failed=$false;try{Assert-InitProvisioningAsset $temp}catch [Management.Automation.CommandNotFoundException]{$failed=$true}
Assert $failed 'runtime wrapper fails when native cmdlet is unavailable without fallback'
$script:missingMetadata=$false
$manifest|Add-Member NoteProperty Password 'forbidden';WriteManifest
$failed=$false;try{Assert-InitProvisioningAsset $temp}catch{$failed=$true}
Assert $failed 'manifest refuses unknown secret fields'
$manifest.PSObject.Properties.Remove('Password');$manifest.CompilerSHA256=('0'*64);WriteManifest
$failed=$false;try{Assert-InitProvisioningAsset $temp}catch{$failed=$true}
Assert $failed 'compiler provenance must match pinned official tool'
Write-Host ('ALL PASS: '+$script:count+' asset validator assertions; synthetic package, metadata mocked')
