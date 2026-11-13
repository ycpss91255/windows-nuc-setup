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
