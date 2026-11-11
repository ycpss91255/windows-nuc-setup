#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
. (Join-Path $root 'script/docker/download_library.ps1')
$fixture=Join-Path $env:TEMP ('container_progress_'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$previousProgress=$ProgressPreference
$script:downloadPreferences=@();$script:failDownload=$false
function Invoke-WebRequest {
 param($Uri,$OutFile,[switch]$UseBasicParsing,$ErrorAction,$TimeoutSec)
 $script:downloadPreferences+=@([string]$ProgressPreference)
 [IO.File]::WriteAllText($OutFile,'owned verified fixture')
 if($script:failDownload){throw 'owned download failure'}
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
 # Real archive/module behavior, including failed extraction and hash gating,
 # is covered in container_archive_tests.ps1 rather than a scope-sharing mock.
} finally {
 $ProgressPreference=$previousProgress
}
