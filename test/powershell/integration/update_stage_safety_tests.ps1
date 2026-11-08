#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('update_stage_safety_'+[guid]::NewGuid().ToString('N'));$fakeData=Join-Path $fixture 'programdata';$outside=Join-Path $fixture 'outside'
[void][IO.Directory]::CreateDirectory($outside);[void][IO.Directory]::CreateDirectory((Join-Path $fakeData 'NUC8-Setup'))
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
$entry=Join-Path $root 'modules/updates/install_windows_updates.ps1';$text=[IO.File]::ReadAllText($entry)
$text=[regex]::Replace($text,'(?im)^#Requires -RunAsAdministrator\s*$','')
# Only test boundary changes: no elevation requirement, TEMP known-folder result, real source identity.
$text=$text.Replace('[Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)',("'"+$fakeData.Replace("'","''")+"'"))
$prefix='$PSScriptRoot='''+(Split-Path $entry).Replace("'","''")+''';$PSCommandPath='''+$entry.Replace("'","''")+''';'
$text=$text.Replace('param([switch]$Worker)','param([switch]$Worker)'+[Environment]::NewLine+$prefix)
$previous=$env:ProgramData;$failure=$null
try{$env:ProgramData=$fakeData;try{& ([scriptblock]::Create($text))}catch{$failure=$_}}finally{$env:ProgramData=$previous}
Assert ($script:registered -eq 0 -and $script:started -eq 0) '不可信stage在SYSTEM註冊與啟動之前拒絕'
Assert (@(Get-ChildItem -LiteralPath $outside -Force).Count -eq 0) 'junction目標未收到任何SYSTEM來源檔'
Assert ($null -ne $failure -and $failure.Exception.Message -ne 'TEST_STOP_NO_REAL_TASK') '實際產品防護拒絕而非測試註冊stub中止'
Assert (Test-Path (Join-Path $fakeData 'NUC8-Setup/WindowsUpdate')) '不刪除舊stage或使用者資料'
Write-Host ('SAFE FIXTURE='+$fixture)