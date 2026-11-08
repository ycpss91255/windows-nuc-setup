#Requires -Version 5.1
param([string]$DriverPackagePath='')
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$manifest=Get-Content -LiteralPath (Join-Path $root 'drivers/nuc8i7hvk_hnk/manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
$required=@{bluetooth_8265=@(
 @{Path='patch_license.txt';SHA256='5B15962179E42A81D8E6C943FDDC8855050FB103B1100CFEE791022378E807CB'},
 @{Path='patch_intel_software_license.rtf';SHA256='301252B14D0111E009353306EA5760A8BCCECD2046F53FC0CA2933F8257D2A34'}
);wifi_8265=@()}
foreach($locale in @('ar-sa','cs-cz','da-dk','de-de','el-gr','en-us','es-es','fi-fi','fr-fr','he-il','hu-hu','it-it','ja-jp','ko-kr','nb-no','nl-nl','pl-pl','pt-br','pt-pt','ru-ru','sv-se','th-th','tr-tr','uk-ua','zh-cn','zh-hk','zh-tw')){$required.wifi_8265+=@{Path=('EULA/'+$locale+'/License.rtf');SHA256='718BD1BDE02C13688F9B48455468982386AB74462FACE0FE32006EF2B5E93A32'}}
foreach($id in @('bluetooth_8265','wifi_8265')){
 $package=@($manifest.Packages|Where-Object Id -ceq $id)[0]
 $zip=$null
 try{
  if($DriverPackagePath){
   $archive=Join-Path $DriverPackagePath $package.File
   Assert ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -eq $package.SHA256) ('實際交付封存檔hash '+$id)
   Add-Type -AssemblyName System.IO.Compression.FileSystem;$zip=[IO.Compression.ZipFile]::OpenRead($archive)
  }
  foreach($file in $required[$id]){
   $pinned=@($package.Files|Where-Object {$_.Path -ceq $file.Path -and $_.SHA256 -eq $file.SHA256})
   Assert ($pinned.Count -eq 1) ('manifest保留原vendor授權位元組 '+$id+'/'+$file.Path)
   if($zip){
    $member=@($zip.Entries|Where-Object {$_.FullName.Replace('\','/') -ceq $file.Path})
    Assert ($member.Count -eq 1) ('實際ZIP保留原vendor授權文件 '+$id+'/'+$file.Path)
    $stream=$member[0].Open();$sha=[Security.Cryptography.SHA256]::Create();try{$hash=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','')}finally{$stream.Dispose();$sha.Dispose()}
    Assert ($hash -eq $file.SHA256) ('實際ZIP授權內容未改寫 '+$id+'/'+$file.Path)
   }
  }
 }finally{if($zip){$zip.Dispose()}}
}
