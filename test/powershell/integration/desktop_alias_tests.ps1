#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../../modules/desktop/desktop_safety.ps1')
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
$fixture=Join-Path $env:TEMP ('desktop_alias_'+[guid]::NewGuid().ToString('N'))
$desktop=Join-Path $fixture 'Desktop Long Name'
$package=Join-Path $desktop 'windows_setup'
$safe=Join-Path $fixture 'safe USB 中文 package'
$null=New-Item -ItemType Directory -Path $package,$safe
[IO.File]::WriteAllText((Join-Path $package 'keep.txt'),'source survives')
$alias=Join-Path $fixture 'usb_alias'
$null=New-Item -ItemType Junction -Path $alias -Target $desktop
$refused=$false;try{Assert-DesktopSourceLocation (Join-Path $alias 'windows_setup') @($desktop)}catch{$refused=$true}
Assert $refused 'reject source ancestor junction outside desktop pointing inside'
$refused=$false;try{Assert-DesktopSourceLocation $safe @($alias)}catch{$refused=$true}
Assert $refused 'reject desktop ancestor reparse instead of assuming distinct physical roots'
$fso=New-Object -ComObject Scripting.FileSystemObject
$short=$fso.GetFolder($desktop).ShortPath
Assert ($short -ne $desktop) 'fixture actually provides an 8.3 alternate path'
$refused=$false;try{Assert-DesktopSourceLocation (Join-Path $short 'windows_setup') @($desktop)}catch{$refused=$true}
Assert $refused 'reject short source ancestor alias within long desktop'
$refused=$false;try{Assert-DesktopSourceLocation $package @($short)}catch{$refused=$true}
Assert $refused 'reject long source within short desktop alias'
Assert-DesktopSourceLocation $safe @($desktop)
Assert $true 'ordinary non-desktop Unicode and spaced directory remains accepted'
Assert (([IO.File]::ReadAllText((Join-Path $package 'keep.txt'))) -eq 'source survives') 'guard never mutates fixture source'
