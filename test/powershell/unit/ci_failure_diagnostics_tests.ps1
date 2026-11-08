#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/test/ci_tasks.ps1')
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
Assert ([bool](Get-Command Write-CIFailureDiagnostics -CommandType Function -ErrorAction SilentlyContinue)) 'CI must expose only approved failed-suite diagnostics'
$temp=Join-Path $env:TEMP ('ci_diagnostics_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
[IO.File]::WriteAllText((Join-Path $temp 'Unit.uac_helpers.log'),"uac expected message`n::warning::literal fixture")
[IO.File]::WriteAllText((Join-Path $temp 'Integration.managed_catalog.log'),'managed mismatch detail')
[IO.File]::WriteAllText((Join-Path $temp 'native_raw.xml'),'never print other private artifacts')
$output=@(Write-CIFailureDiagnostics -ReportDirectory $temp)
$text=$output -join "`n"
Assert ($text.Contains('uac expected message') -and $text.Contains('managed mismatch detail')) 'fixed real suite log names are read from the supplied report directory'
Assert (-not $text.Contains('never print other private artifacts')) 'diagnostics do not enumerate or read unrelated logs and raw artifacts'
Assert ($text.Contains('    ::warning::literal fixture') -and -not @($output|Where-Object {$_ -match '^::'}).Count) 'log lines are prefixed so fixture content cannot emit workflow commands'
$rejected=$false;try{Write-CIFailureDiagnostics -ReportDirectory $temp -SuiteNames @('Unit.uac_helpers','../native_raw')|Out-Null}catch{$rejected=$true}
Assert $rejected 'unknown or traversal suite names fail instead of allowing arbitrary file reads'
$only=@(Write-CIFailureDiagnostics -ReportDirectory $temp -SuiteNames @('Unit.uac_helpers')) -join "`n"
Assert ($only.Contains('uac expected message') -and -not $only.Contains('managed mismatch detail')) 'explicit allowed subset cannot expand to every log'
$absent=@(Write-CIFailureDiagnostics -ReportDirectory (Join-Path $temp 'not-created')) -join "`n"
Assert ($absent.Contains('Unit.uac_helpers.log') -and $absent.Contains('unavailable') -and -not $absent.Contains($temp)) 'early CI failure reports missing diagnostics without leaking absolute paths or replacing original error'
[IO.File]::WriteAllLines((Join-Path $temp 'Unit.uac_helpers.log'),@(1..100|ForEach-Object {'safe-line-'+$_}))
$tail=@(Write-CIFailureDiagnostics -ReportDirectory $temp -SuiteNames @('Unit.uac_helpers')) -join "`n"
Assert ($tail.Contains('safe-line-100') -and -not $tail.Contains('safe-line-20')) 'failure console output retains a bounded final eighty lines'
$fixed=@('Unit.driver_cache_cleanup','Integration.init_runtime','Integration.driver_full_source_coverage')
foreach($suite in $fixed){[IO.File]::WriteAllText((Join-Path $temp ($suite+'.log')),('safe fixture details '+$suite))}
$accepted=$true;try{$details=@(Write-CIFailureDiagnostics -ReportDirectory $temp -SuiteNames $fixed) -join "`n"}catch{$accepted=$false}
Assert ($accepted -and $details.Contains('safe fixture details Unit.driver_cache_cleanup') -and $details.Contains('safe fixture details Integration.init_runtime') -and $details.Contains('safe fixture details Integration.driver_full_source_coverage')) '固定安全驅動與Init診斷可讀回實值，不擴張任意log白名單'