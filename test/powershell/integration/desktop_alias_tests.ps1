#Requires -Version 5.1
param([switch]$SimulateNoShortAlias)
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
$short=if($SimulateNoShortAlias){$desktop}else{$fso.GetFolder($desktop).ShortPath}
if($short -ne $desktop){
 Write-Host ('8.3 fixture: '+(Split-Path $short -Leaf)+' -> '+(Get-Item -LiteralPath $short).Name)
 $refused=$false;try{Assert-DesktopSourceLocation (Join-Path $short 'windows_setup') @($desktop)}catch{$refused=$true}
 Assert $refused 'reject short source ancestor alias within long desktop'
 $refused=$false;try{Assert-DesktopSourceLocation $package @($short)}catch{$refused=$true}
 Assert $refused 'reject long source within short desktop alias'
}else{
 Write-Host 'Fixture provider has no 8.3 alias; real short-alias cases were not exercised in this mode.'
 Assert ($short -eq $desktop) 'provider exposes no alternate short path (not short-alias behavior evidence)'
}
# Provider boundary contract is separate from the actual filesystem cases above.
& {
 function Get-Item {param($LiteralPath,[switch]$Force,$ErrorAction);[pscustomobject]@{PSIsContainer=$true;FullName='C:\Safe USB\Expanded Directory';Attributes=[IO.FileAttributes]::Directory;Parent=$null}}
 Assert ((Get-DesktopSafeLongDirectory 'C:\SAFEUS~1\EXPAND~1') -ceq 'C:\Safe USB\Expanded Directory') 'normalizer uses provider long name rather than input spelling'
}
Assert-DesktopSourceLocation $safe @($desktop)
Assert $true 'ordinary non-desktop Unicode and spaced directory remains accepted'
Assert (([IO.File]::ReadAllText((Join-Path $package 'keep.txt'))) -eq 'source survives') 'guard never mutates fixture source'
