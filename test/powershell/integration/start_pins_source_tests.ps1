#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/start_menu/start_pins_asset_library.ps1')
$asset=Assert-StartPinsAssetSource (Join-Path $root 'modules/start_menu/assets')
Write-Host ('@@ASSERT@@'+(@{Name='physical Start policy source package hashes and exact XML validated';Passed=($asset.PackageName -ceq 'windows_setup_empty_start')}|ConvertTo-Json -Compress))
