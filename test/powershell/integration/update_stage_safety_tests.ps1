#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/updates/update_entry_library.ps1')
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
Assert ([bool](Get-Command Invoke-SetupWindowsUpdateEntry -ErrorAction SilentlyContinue)) '安全fixture必須直接載入正式具名更新入口而非複製薄入口文字'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('update_stage_safety_'+[guid]::NewGuid().ToString('N'));$fakeData=Join-Path $fixture 'programdata';$outside=Join-Path $fixture 'outside'
[void][IO.Directory]::CreateDirectory($outside);[void][IO.Directory]::CreateDirectory((Join-Path $fakeData 'NUC8-Setup'))
$fakeData=[IO.Path]::GetFullPath($fakeData)
$script:expectedCommonDataRoot=$fakeData;$script:fixtureCommonDataRoot=$fakeData;$script:commonRootReads=0
function Get-SetupWindowsUpdateCommonDataRoot {
 if($script:fixtureCommonDataRoot -cne $script:expectedCommonDataRoot){throw 'TEST_BOUNDARY_COMMONDATA: refusing any non-fixture root.'}
 $script:commonRootReads++
 return $script:fixtureCommonDataRoot
}
$script:fixtureCommonDataRoot=$outside;$boundaryRejected=$false
try{Get-SetupWindowsUpdateCommonDataRoot|Out-Null}catch{$boundaryRejected=$_.Exception.Message.StartsWith('TEST_BOUNDARY_COMMONDATA:')}
Assert ($boundaryRejected -and $script:commonRootReads -eq 0) 'KnownFolder替身拒絕任何非精確fakeData根，未進產品寫入'
$script:fixtureCommonDataRoot=$fakeData
$null=New-Item -ItemType Junction -Path (Join-Path $fakeData 'NUC8-Setup/WindowsUpdate') -Target $outside
# Also reserve the new private root as a hostile link; never touch actual CommonApplicationData.
$null=New-Item -ItemType Junction -Path (Join-Path $fakeData 'windows_setup_update') -Target $outside
$script:registered=0;$script:started=0
function Get-ScheduledTask {param($TaskName,$ErrorAction) return $null}
function New-ScheduledTaskAction {param($Execute,$Argument) [pscustomobject]@{Execute=$Execute;Argument=$Argument}}
function New-ScheduledTaskPrincipal {param($UserId,$LogonType,$RunLevel) [pscustomobject]@{UserId=$UserId}}
function New-ScheduledTaskSettingsSet {param($ExecutionTimeLimit,[switch]$StartWhenAvailable,[switch]$AllowStartIfOnBatteries,[switch]$DontStopIfGoingOnBatteries) [pscustomobject]@{Fixture=$true}}
function Register-ScheduledTask {param($TaskName,$Action,$Principal,$Settings,[switch]$Force) $script:registered++;throw 'TEST_STOP_NO_REAL_TASK'}
function Start-ScheduledTask {$script:started++;throw 'TEST_STOP_NO_START'}
$entry=Join-Path $root 'modules/updates/install_windows_updates.ps1';$failure=$null
try{Invoke-SetupWindowsUpdateEntry -EntryPath $entry -ModuleRoot (Split-Path $entry -Parent)}catch{if($_.Exception.Message.StartsWith('TEST_BOUNDARY_')){throw};$failure=$_}
Assert ($script:commonRootReads -eq 1) '正式入口透過唯一KnownFolder邊界讀取精確TEMP根'
Assert ($script:registered -eq 0 -and $script:started -eq 0) '不可信stage在SYSTEM註冊與啟動之前拒絕'
Assert (@(Get-ChildItem -LiteralPath $outside -Force).Count -eq 0) 'junction目標未收到任何SYSTEM來源檔'
Assert ($null -ne $failure -and $failure.Exception.Message -ne 'TEST_STOP_NO_REAL_TASK') '實際產品防護拒絕而非測試註冊stub中止'
Assert (Test-Path (Join-Path $fakeData 'NUC8-Setup/WindowsUpdate')) '不刪除舊stage或使用者資料'
Write-Host ('SAFE FIXTURE='+$fixture)
