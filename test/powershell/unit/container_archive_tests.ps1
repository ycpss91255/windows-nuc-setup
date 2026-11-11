#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
. (Join-Path $root 'script/docker/download_library.ps1')
Add-Type -AssemblyName System.IO.Compression.FileSystem
$fixture=Join-Path $env:TEMP ("container archive 中文 ' "+[guid]::NewGuid().ToString('N'))
$sourceDirectory=Join-Path $fixture 'input';[void][IO.Directory]::CreateDirectory($sourceDirectory)
[IO.File]::WriteAllText((Join-Path $sourceDirectory 'owned.txt'),'owned native archive bytes')
$archive=Join-Path $fixture 'owned.zip'
[IO.Compression.ZipFile]::CreateFromDirectory($sourceDirectory,$archive)
$previousProgress=$ProgressPreference
try {
 foreach($initial in @('Continue','Stop')){
  $ProgressPreference=$initial
  $destination=Join-Path $fixture ('output_'+$initial)
  $accepted=$true
  try{Expand-ContainerToolArchive -LiteralPath $archive -DestinationPath $destination}catch{$accepted=$false}
  Assert $accepted ('真實 ZIP 解壓不受呼叫端原生進度偏好影響：'+$initial)
  Assert ([IO.File]::ReadAllText((Join-Path $destination 'owned.txt')) -ceq 'owned native archive bytes') '真實解壓保留位元組與含中文單引號路徑'
  Assert ([string]$ProgressPreference -ceq $initial) '真實解壓成功不改呼叫端進度偏好'
  $failed=$false
  try{Expand-ContainerToolArchive -LiteralPath $archive -DestinationPath $destination}catch{$failed=$true}
  Assert ($failed -and [IO.File]::ReadAllText((Join-Path $destination 'owned.txt')) -ceq 'owned native archive bytes') '重複檔案解壓失敗且不覆寫既有位元組'
  Assert ([string]$ProgressPreference -ceq $initial) '真實解壓失敗不改呼叫端進度偏好'
 }
 $literalArchive=Join-Path $fixture '[literal].zip';[IO.File]::Copy($archive,$literalArchive)
 $literalDestination=Join-Path $fixture 'literal_output'
 Expand-ContainerToolArchive -LiteralPath $literalArchive -DestinationPath $literalDestination
 Assert ([IO.File]::ReadAllText((Join-Path $literalDestination 'owned.txt')) -ceq 'owned native archive bytes') '中括號 ZIP 名稱以完整字面路徑解壓'
 $corrupt=Join-Path $fixture 'corrupt.zip';[IO.File]::WriteAllText($corrupt,'not a zip')
 $failed=$false
 try{Expand-ContainerToolArchive -LiteralPath $corrupt -DestinationPath (Join-Path $fixture 'corrupt_output')}catch{$failed=$true}
 Assert ($failed -and [string]$ProgressPreference -ceq 'Stop') '損壞 ZIP 失敗且不吞錯或改進度偏好'
 $escape=Join-Path $fixture 'escape.zip'
 $zip=[IO.Compression.ZipFile]::Open($escape,[IO.Compression.ZipArchiveMode]::Create)
 try{$entry=$zip.CreateEntry('../escaped.txt');$writer=[IO.StreamWriter]::new($entry.Open());try{$writer.Write('must not escape')}finally{$writer.Dispose()}}finally{$zip.Dispose()}
 $failed=$false
 try{Expand-ContainerToolArchive -LiteralPath $escape -DestinationPath (Join-Path $fixture 'bounded_output')}catch{$failed=$true}
 Assert ($failed -and -not [IO.File]::Exists((Join-Path $fixture 'escaped.txt'))) 'ZIP 上層穿越被拒絕且不寫出目的地'
 . (Join-Path $root 'script/docker/install_managed_tools.ps1')
 function Invoke-WebRequest {param($Uri,$OutFile,[switch]$UseBasicParsing,$ErrorAction,$TimeoutSec);[IO.File]::Copy($archive,$OutFile)}
 $artifact=[pscustomobject]@{Name='managed.zip';Uri='https://example.invalid/owned.zip';Algorithm='SHA256';Hash=(Get-FileHash -LiteralPath $archive).Hash;Kind='Zip'}
 $destination=Join-Path $fixture 'managed';$downloads=Join-Path $fixture 'downloads'
 Install-ContainerToolArtifact -Artifact $artifact -Destination $destination -ArchiveDirectory $downloads
 Assert ([IO.File]::ReadAllText((Join-Path $destination 'owned.txt')) -ceq 'owned native archive bytes') '正式 managed 安裝器驗真雜湊後進行真實 ZIP 解壓'
 Assert ([string]$ProgressPreference -ceq 'Stop') '正式安裝器成功仍保留呼叫端進度偏好'
 $artifact.Hash='0'*64;$failed=$false;$badDestination=Join-Path $fixture 'bad_digest'
 try{Install-ContainerToolArtifact -Artifact $artifact -Destination $badDestination -ArchiveDirectory $downloads}catch{$failed=$_.Exception.Message -like '*digest mismatch*'}
 Assert ($failed -and -not [IO.Directory]::Exists($badDestination)) '錯誤雜湊在真實解壓及目的地建立前拒絕'
 Assert ([string]$ProgressPreference -ceq 'Stop' -and -not [IO.File]::Exists((Join-Path $downloads 'managed.zip'))) '正式安裝器失敗恢復進度且清理未信任下載'
} finally {$ProgressPreference=$previousProgress}
