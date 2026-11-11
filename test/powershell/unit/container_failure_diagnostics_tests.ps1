#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
. (Join-Path $root 'script/test/ci_tasks.ps1')
Assert ([bool](Get-Command Write-CIContainerFailureDiagnostics -ErrorAction SilentlyContinue)) 'container failure must expose bounded diagnostics from fixed failed coverage suites'
$fixture=Join-Path $env:TEMP ('container_diagnostics_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'public'))
@{Checks=@(@{Name='Integration.powershell_engine';Passed=$false},@{Name='Unit.terminal_helpers';Passed=$false},@{Name='Integration.powershell_coverage';Passed=$true},@{Name='secret';Passed=$false})}|ConvertTo-Json -Depth 4|Set-Content (Join-Path $fixture 'public/summary.json') -Encoding UTF8
1..100|ForEach-Object {'line '+$_}|Set-Content (Join-Path $fixture 'Integration.powershell_engine.log') -Encoding UTF8
Add-Content (Join-Path $fixture 'Integration.powershell_engine.log') '::error::inert diagnostic'
1..100|ForEach-Object {'terminal line '+$_}|Set-Content (Join-Path $fixture 'Unit.terminal_helpers.log') -Encoding UTF8
Add-Content (Join-Path $fixture 'Unit.terminal_helpers.log') 'TERMINAL_CONTEXT_FAILURE'
Set-Content (Join-Path $fixture 'secret.log') 'PRIVATE_DO_NOT_READ'
Set-Content (Join-Path $fixture 'Integration.powershell_coverage.log') 'PASSED_DO_NOT_READ'
$lines=@(Write-CIContainerFailureDiagnostics -ReportDirectory $fixture);$text=$lines -join "`n"
Assert ($lines.Count -eq 162 -and $lines[0] -eq 'CI diagnostic: Integration.powershell_engine.log') 'each failed fixed suite including Terminal receives exactly an eighty-line console tail'
Assert ($text.Contains('CI diagnostic: Unit.terminal_helpers.log') -and $text.Contains('    TERMINAL_CONTEXT_FAILURE') -and $text.Contains('    terminal line 22') -and -not $text.Contains('    terminal line 21')) 'Terminal context failure is visible without broad arbitrary log access'
Assert ($text.Contains('    line 22') -and -not $text.Contains('    line 21')) 'tail limit is exactly eighty lines'
Assert ($text.Contains('    ::error::inert diagnostic') -and -not $text.Contains("`n::error::")) 'workflow command text stays prefixed and inert'
Assert (-not $text.Contains('PRIVATE_DO_NOT_READ') -and -not $text.Contains('PASSED_DO_NOT_READ')) 'unknown and successful suites are never read'
$empty=Join-Path $fixture 'missing';[void][IO.Directory]::CreateDirectory($empty)
Assert ((@(Write-CIContainerFailureDiagnostics -ReportDirectory $empty) -join '') -eq 'Container failure diagnostics unavailable before report generation.') 'early failure remains diagnosable without inventing report success'
$runner=[IO.File]::ReadAllText((Join-Path $root 'script/docker/container_test.ps1'))
Assert ($runner -match 'catch\s*\{[\s\S]*Write-CIContainerFailureDiagnostics' -and $runner -match 'exit 1') 'actual container failure path emits diagnostics while preserving nonzero exit'
