#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$SourceRoot,[Parameter(Mandatory=$true)][string]$PackagePath)
$ErrorActionPreference='Stop'
$expected='B8yVwiGkpN9LU8q7cBZHgBtBIAKgW+FbpVA/ZtSHD65K1FWFTT7nSVfehKL2OuoyufPf8VNcaRfHUTB3Rb3RZQ=='
if(-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)){throw '格式檢查套件不存在，拒絕網路回退。'}
$actual=[Convert]::ToBase64String((New-Object Security.Cryptography.SHA512Managed).ComputeHash([IO.File]::ReadAllBytes([IO.Path]::GetFullPath($PackagePath))))
if($actual -cne $expected){throw '格式檢查套件 SHA512 不符。'}
$root=[IO.Path]::GetFullPath($SourceRoot)
$files=@('modules/native/managed_source_library.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('pssa_format_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp -ErrorAction Stop|Out-Null
try{
 Add-Type -AssemblyName System.IO.Compression.FileSystem
 [IO.Compression.ZipFile]::ExtractToDirectory([IO.Path]::GetFullPath($PackagePath),$temp)
 $settings=Join-Path $PSScriptRoot 'pssa_settings.psd1'
 foreach($relative in $files){
  $file=Join-Path $root $relative
  if(-not (Test-Path -LiteralPath $file -PathType Leaf)){throw ('格式檢查來源不存在：'+$relative)}
  $job=Start-Job -ArgumentList @((Join-Path $temp 'PSScriptAnalyzer.psd1'),$file,$settings) -ScriptBlock {
   param($module,$target,$configuration)
   $ErrorActionPreference='Stop'
   Import-Module $module -Force -ErrorAction Stop
   if((Get-Module PSScriptAnalyzer).Version -ne [version]'1.24.0'){throw '格式檢查套件版本不符。'}
   @(Invoke-ScriptAnalyzer -Path $target -Settings $configuration)
  }
  try{
   $diagnostics=@(Receive-Job -Job $job -Wait -ErrorAction Stop)
   if($job.State -ne 'Completed'){throw '格式檢查程序失敗。'}
   if($diagnostics.Count){$diagnostics|ForEach-Object {Write-Host ($relative+':'+$_.Line+' '+$_.RuleName)};throw '格式檢查未通過。'}
  } finally {Remove-Job -Job $job -Force -ErrorAction SilentlyContinue}
 }
 Write-Host ('格式檢查通過（限定 '+$files.Count+' 檔）。')
} finally {
 Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction Stop
}