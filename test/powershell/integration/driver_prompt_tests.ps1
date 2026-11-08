#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$fixture=Join-Path $env:TEMP ('windows_setup_driver_prompt_'+[guid]::NewGuid().ToString('N'))
$core=Join-Path $fixture 'windows_setup/core'
New-Item -ItemType Directory -Path $core -Force|Out-Null
Copy-Item (Join-Path $root 'core/start_windows.ps1'),(Join-Path $root 'core/hardware.ps1') -Destination $core
[IO.File]::WriteAllText((Join-Path $core 'configure_nuc.ps1'),'param($DriverPackagePath);$script:SelectedDriver=$DriverPackagePath',[Text.UTF8Encoding]::new($true))
$count=0
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Message)};$script:count++}
function Get-CimInstance {param($ClassName,$ErrorAction);[pscustomobject]@{Product=$script:Board}}
function Read-Host {param($Prompt);$script:PromptCount++;if(-not $script:Answers.Count){throw '不應詢問此機型的 NUC 驅動包'};$answer=$script:Answers.Dequeue();return $answer}
$script:Board='Other Board';$script:PromptCount=0;$script:Answers=New-Object 'Collections.Generic.Queue[string]'
& (Join-Path $core 'start_windows.ps1')
Assert ($script:PromptCount -eq 0 -and -not $script:SelectedDriver) '一般電腦自動使用通用設定，不詢問 NUC 包'
$script:Board='NUC8i7HVB';$script:Answers.Enqueue('')
& (Join-Path $core 'start_windows.ps1')
Assert (-not $script:SelectedDriver) '支援 NUC 可直接 Enter 略過驅動'
Write-Host ('ALL PASS: '+$count+' driver prompt assertions; no host changes.')