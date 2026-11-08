#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$fixture=Join-Path $env:TEMP ('windows_setup_driver_prompt_'+[guid]::NewGuid().ToString('N'))
$core=Join-Path $fixture 'windows_setup/core'
New-Item -ItemType Directory -Path $core -Force|Out-Null
Copy-Item (Join-Path $root 'core/start_windows.ps1'),(Join-Path $root 'core/hardware.ps1') -Destination $core
[IO.File]::WriteAllText((Join-Path $core 'configure_nuc.ps1'),'param($DriverPackagePath);$fixtureState.SelectedDriver=$DriverPackagePath',[Text.UTF8Encoding]::new($true))
$fixtureState=@{Board='';PromptCount=0;Answers=$null;SelectedDriver=''};$count=0
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Message)};$script:count++}
function Get-CimInstance {param($ClassName,$ErrorAction);[pscustomobject]@{Product=$fixtureState.Board}}
function Read-Host {param($Prompt);$fixtureState.PromptCount++;if(-not $fixtureState.Answers.Count){throw '不應詢問此機型的 NUC 驅動包'};$answer=$fixtureState.Answers.Dequeue();return $answer}
$fixtureState.Board='Other Board';$fixtureState.PromptCount=0;$fixtureState.Answers=New-Object 'Collections.Generic.Queue[string]'
& (Join-Path $core 'start_windows.ps1')
Assert ($fixtureState.PromptCount -eq 0 -and -not $fixtureState.SelectedDriver) '一般電腦自動使用通用設定，不詢問 NUC 包'
$fixtureState.Board='NUC8i7HVB';$fixtureState.Answers.Enqueue('')
& (Join-Path $core 'start_windows.ps1')
Assert ($fixtureState.PromptCount -eq 1 -and -not $fixtureState.SelectedDriver) '支援 NUC 可直接 Enter 略過驅動'
Write-Host ('ALL PASS: '+$count+' driver prompt assertions; no host changes.')