#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Version,[Parameter(Mandatory=$true)][string]$Repository,[Parameter(Mandatory=$true)][string]$AssetDirectory,[string]$MetadataPath=(Join-Path $PSScriptRoot 'driver_release_assets.json'))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'driver_release_library.ps1')
Invoke-StageDriverRelease -Version $Version -Repository $Repository -AssetDirectory $AssetDirectory -MetadataPath $MetadataPath -PackageRoot ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')))
