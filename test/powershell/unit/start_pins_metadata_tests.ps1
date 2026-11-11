#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/start_menu/start_pins_asset_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
Assert ([bool](Get-Command Assert-StartPinsAsset -ErrorAction SilentlyContinue)) 'runtime has mandatory native metadata composition'
$script:calls=0;$script:sourceFails=$false;$script:wrong=$false
function Assert-StartPinsAssetSource {param($AssetRoot);if($script:sourceFails){throw 'source invalid'};[pscustomobject]@{PackageId='73c18f23-529e-4379-a458-4c9b3a8d5b92';PackageName='windows_setup_empty_start';PackageVersion='1.0'}}
function Get-ProvisioningPackage {param($PackagePath,$LogsDirectoryPath,$ErrorAction);$script:calls++;[pscustomobject]@{PackageID='73c18f23-529e-4379-a458-4c9b3a8d5b92';PackageName=$(if($script:wrong){'wrong'}else{'windows_setup_empty_start'});Version='1.0';Rank=0;OwnerType=5000}}
$null=Assert-StartPinsAsset $env:TEMP
Assert ($script:calls -eq 1) 'valid source always reaches native metadata'
$script:sourceFails=$true;$failed=$false;try{Assert-StartPinsAsset $env:TEMP}catch{$failed=$true}
Assert ($failed -and $script:calls -eq 1) 'invalid source never reaches native metadata'
$script:sourceFails=$false;$script:wrong=$true;$failed=$false;try{Assert-StartPinsAsset $env:TEMP}catch{$failed=$true}
Assert $failed 'native package identity mismatch fails'
