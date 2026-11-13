#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$support=Join-Path $root 'test/powershell/support/runner_probe_diagnostic.ps1'
Assert (Test-Path -LiteralPath $support -PathType Leaf) 'probe fixture 提供可供公開報告的固定診斷'
. $support
$names=@(Get-RunnerProbeDiagnostic -Phase 'query' -HasPid $true -Message 'Docker readiness stage=probe category=process-deadline elapsed_ms=100 remaining_ms=900')
Assert (($names -join '|') -eq 'probe diagnostic phase=query|probe diagnostic pid=present|probe diagnostic category=process-deadline') '辨識已知階段 PID 與受控 deadline 類別'
$names=@(Get-RunnerProbeDiagnostic -Phase 'private C:\secret' -HasPid $false -Message 'secret C:\private')
Assert (($names -join '|') -eq 'probe diagnostic phase=unknown|probe diagnostic pid=absent|probe diagnostic category=unknown') '未知內容不得進入公開診斷'
Assert ($null -ne (Get-Command Get-RunnerProbeNativeKind -ErrorAction SilentlyContinue)) '首次原生呼叫提供受限內部例外分類'
foreach($case in @(
 @{Message='runner-process-deadline-cleaned';Expected='process-cleaned'},
 @{Message='runner-process-deadline';Expected='process-deadline'},
 @{Message='runner-output-deadline';Expected='output-deadline'}
)) {Assert ((Get-RunnerProbeNativeKind ([TimeoutException]::new($case.Message))) -ceq $case.Expected) ('固定 timeout 類別 '+$case.Expected)}
Assert ((Get-RunnerProbeNativeKind ([Exception]::new('Runner prerequisite process cleanup failed.'))) -ceq 'cleanup-unconfirmed') '確認清理失敗分類'
Assert ((Get-RunnerProbeNativeKind ([Exception]::new('runner-process-deadline-cleaned'))) -ceq 'unknown') '錯誤型別不能偽造已清理訊號'
Assert ((Get-RunnerProbeNativeKind ([Exception]::new('C:\private\secret'))) -ceq 'unknown') '未知例外不輸出私人內容'
$names=@(Get-RunnerProbeDiagnostic -Phase 'probe' -HasPid $true -Message 'private' -NativeKind 'private C:\secret' -NativeElapsedMilliseconds 123)
Assert ($names -contains 'probe diagnostic native_kind=unknown' -and $names -contains 'probe diagnostic native_elapsed_ms=123' -and ($names -join '|') -notmatch 'private|secret') '僅輸出受控分類與實際計時整數'
