#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Version,[string]$PackageRoot)
$ErrorActionPreference='Stop'
if(-not $PackageRoot){$PackageRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))}
. (Join-Path $PSScriptRoot 'release.ps1')
$null=Get-ReleaseVersion $Version
$path=Join-Path $PackageRoot 'doc/changelog/changelog.md'
$text=[IO.File]::ReadAllText($path)
if(([regex]::Matches($text,'(?m)^## \[Unreleased\]\s*$')).Count -ne 1){throw '必須有且只有一個 ## [Unreleased] 章節。'}
if($text -match ('(?m)^## \[?'+[regex]::Escape($Version)+'(?:\]|\s|$)')){throw '版本章節已存在，未覆寫。'}
$new=[regex]::Replace($text,'(?m)^## \[Unreleased\]\s*$',("## [Unreleased]`n`n## [$Version] — "+(Get-Date -Format 'yyyy-MM-dd')),1)
$null=Get-ReleaseNotes $Version $new
[IO.File]::WriteAllText($path,$new,[Text.UTF8Encoding]::new($true))
[IO.File]::WriteAllText((Join-Path $PackageRoot '.version'),($Version+"`n"),[Text.UTF8Encoding]::new($false))
Write-Host '已同步 .version 與變更紀錄；請執行測試、提交 PR，合併後才建立並推送相同版本標籤。未建立提交或標籤。'
