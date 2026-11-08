#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'core/configuration_library.ps1')
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
$fixture=Join-Path $env:TEMP ('credential_progress_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture);$fixture=[IO.Path]::GetFullPath($fixture)
[IO.File]::WriteAllText((Join-Path $fixture 'start_pins_policy_library.ps1'),'# inert module boundary')
[IO.File]::WriteAllText((Join-Path $fixture 'apply_uac_settings.ps1'),'# no host changes')
[IO.File]::WriteAllText((Join-Path $fixture 'apply_autologon_settings.ps1'),@'
param($UserName,$AutoLogonPassword)
$global:credentialProgressPromptReached=$true
if($global:credentialProgressActive){throw 'credential prompt entered while progress panel is active'}
throw 'controlled credential boundary reached without a progress panel'
'@,[Text.UTF8Encoding]::new($true))
function Resolve-NucPath {param($Name) Join-Path $fixture $Name}
function Start-Transcript {param($Path)}
function Stop-Transcript {$global:credentialProgressStopped=$true}
function Write-Progress {param($Id,$Activity,$Status,$PercentComplete,[switch]$Completed) $global:credentialProgressActive=-not [bool]$Completed}
$global:credentialProgressActive=$false;$global:credentialProgressPromptReached=$false;$global:credentialProgressStopped=$false;$caught=$null
try{Invoke-SetupConfiguration -Hardware ([pscustomobject]@{}) -UserName fixture}catch{$caught=$_}
Assert ($global:credentialProgressPromptReached -and $caught.Exception.Message -ceq 'controlled credential boundary reached without a progress panel') '原始主流程在帳密模組開始前不得保留進度面板；不是僅驗ReadHost替身'
Assert $global:credentialProgressStopped '密碼輸入邊界失敗仍確實關閉transcript'
[IO.File]::WriteAllText((Join-Path $fixture 'apply_autologon_settings.ps1'),@'
param($UserName,$AutoLogonPassword)
if($global:credentialProgressActive){throw 'credential prompt entered while progress panel is active'}
$global:credentialProgressPromptReached=$true
'@,[Text.UTF8Encoding]::new($true))
function Get-ItemProperty {param($Path) $global:credentialProgressAfterPrompt=$global:credentialProgressActive;throw 'controlled post-credential native boundary'}
$global:credentialProgressPromptReached=$false;$global:credentialProgressActive=$false;$global:credentialProgressAfterPrompt=$false;$caught=$null
try{Invoke-SetupConfiguration -Hardware ([pscustomobject]@{}) -UserName fixture}catch{$caught=$_}
Assert ($global:credentialProgressPromptReached -and $global:credentialProgressAfterPrompt -and $caught.Exception.Message -ceq 'controlled post-credential native boundary') '帳密模組返回之後恢復進度，後續原生讀取錯誤仍保留'
