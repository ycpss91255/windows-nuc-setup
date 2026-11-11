#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
. (Join-Path $root 'script/docker/download_library.ps1')
$fixture=Join-Path $env:TEMP ('container_progress_'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$previousProgress=$ProgressPreference
$script:downloadPreferences=@();$script:extractionPreferences=@();$script:failDownload=$false;$script:failExtraction=$false
function Invoke-WebRequest {
 param($Uri,$OutFile,[switch]$UseBasicParsing,$ErrorAction,$TimeoutSec)
 $script:downloadPreferences+=@([string]$ProgressPreference)
 [IO.File]::WriteAllText($OutFile,'owned verified fixture')
 if($script:failDownload){throw 'owned download failure'}
}
function Expand-Archive {
 param($LiteralPath,$DestinationPath)
 $script:extractionPreferences+=@([string]$ProgressPreference)
 if($script:failExtraction){throw 'owned extraction failure'}
 [IO.File]::WriteAllText((Join-Path $fixture 'extracted.marker'),$DestinationPath)
}
try {
 foreach($initial in @('Continue','Stop')){
  $ProgressPreference=$initial
  $target=Join-Path $fixture ($initial+'.zip')
  Invoke-ContainerOfficialDownload -Uri 'https://example.invalid/owned.zip' -OutFile $target
  Assert ($script:downloadPreferences[-1] -ceq 'SilentlyContinue') '官方工具下載只在當次呼叫停用原生進度'
  Assert ([string]$ProgressPreference -ceq $initial -and [IO.File]::ReadAllText($target) -ceq 'owned verified fixture') '下載成功保留原始位元組並恢復呼叫端進度偏好'
  $script:failDownload=$true;$message=''
  try{Invoke-ContainerOfficialDownload -Uri 'https://example.invalid/owned.zip' -OutFile (Join-Path $fixture ($initial+'_failed.zip'))}catch{$message=$_.Exception.Message}
  Assert ($message -ceq 'owned download failure' -and $script:downloadPreferences[-1] -ceq 'SilentlyContinue' -and [string]$ProgressPreference -ceq $initial) '下載失敗仍傳遞原錯誤並恢復進度偏好'
  Assert (@(Get-ChildItem -LiteralPath $fixture -Filter '*.partial' -File).Count -eq 0) '下載失敗不留下半檔'
  $script:failDownload=$false
 }
 Assert ([bool](Get-Command Expand-ContainerToolArchive -ErrorAction SilentlyContinue)) '工具解壓具有局部進度範圍'
 foreach($initial in @('Continue','Stop')){
  $ProgressPreference=$initial
  Expand-ContainerToolArchive -LiteralPath (Join-Path $fixture 'Continue.zip') -DestinationPath $fixture
  Assert ($script:extractionPreferences[-1] -ceq 'SilentlyContinue' -and [string]$ProgressPreference -ceq $initial) '工具解壓成功只抑制當次原生進度'
  $script:failExtraction=$true;$message=''
  try{Expand-ContainerToolArchive -LiteralPath (Join-Path $fixture 'Continue.zip') -DestinationPath $fixture}catch{$message=$_.Exception.Message}
  Assert ($message -ceq 'owned extraction failure' -and $script:extractionPreferences[-1] -ceq 'SilentlyContinue' -and [string]$ProgressPreference -ceq $initial) '解壓失敗不吞錯且恢復呼叫端進度偏好'
  $script:failExtraction=$false
 }
 . (Join-Path $root 'script/docker/install_managed_tools.ps1')
 $artifact=[pscustomobject]@{Name='managed.zip';Uri='https://example.invalid/owned.zip';Algorithm='SHA256';Hash=(Get-FileHash -LiteralPath (Join-Path $fixture 'Continue.zip')).Hash;Kind='Zip'}
 $count=$script:extractionPreferences.Count
 Install-ContainerToolArtifact -Artifact $artifact -Destination $fixture -ArchiveDirectory (Join-Path $fixture 'archives')
 Assert ($script:extractionPreferences.Count -eq $count+1 -and $script:extractionPreferences[-1] -ceq 'SilentlyContinue') '正式 managed 安裝器經真實雜湊驗證後使用局部解壓範圍'
 $artifact.Hash='0'*64;$message='';$count=$script:extractionPreferences.Count
 try{Install-ContainerToolArtifact -Artifact $artifact -Destination $fixture -ArchiveDirectory (Join-Path $fixture 'archives')}catch{$message=$_.Exception.Message}
 Assert ($message -like '*digest mismatch*' -and $script:extractionPreferences.Count -eq $count) '錯誤雜湊仍在解壓前拒絕'
} finally {
 $ProgressPreference=$previousProgress
}
