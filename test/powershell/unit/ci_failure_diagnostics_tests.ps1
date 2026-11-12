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
[IO.File]::WriteAllLines((Join-Path $temp 'Integration.report_bundle_publication.log'),[string[]]@('PRIVATE-CREDENTIAL-SENTINEL C:\Users\private','@@SAFE_FIXTURE_DIAG@@fixture_export:go_fixture_failed','@@SAFE_FIXTURE_DIAG@@fixture_export:go_fixture_failed','@@SAFE_FIXTURE_DIAG@@fixture_export:unknown'))
$safeAccepted=$true;try{$safeOutput=@(Write-CIFailureDiagnostics -ReportDirectory $temp -SuiteNames @('Integration.report_bundle_publication')) -join "`n"}catch{$safeAccepted=$false;$safeOutput=''}
Assert ($safeAccepted -and $safeOutput.Contains('fixture_export:go_fixture_failed')) '原生 All 只呈現合成工件固定失敗代碼'
Assert (-not $safeOutput.Contains('PRIVATE-CREDENTIAL-SENTINEL') -and -not $safeOutput.Contains('C:\Users') -and -not $safeOutput.Contains('unknown')) '原生 All 不公開原始私人日誌或未知代碼'
Assert (([regex]::Matches($safeOutput,'fixture_export:go_fixture_failed')).Count -eq 1) '重複固定代碼輸出有界'
[IO.File]::WriteAllText((Join-Path $temp 'Integration.report_bundle_publication.log'),('x'*(4MB+1)))
$oversized=@(Write-CIFailureDiagnostics -ReportDirectory $temp -SuiteNames @('Integration.report_bundle_publication')) -join "`n"
Assert ($oversized.Contains('unavailable') -and $oversized.Length -lt 256) '大型私有日誌不讀取或公開'
$workflow=[IO.File]::ReadAllText((Join-Path $root '.github/workflows/windows_tests.yml'))
Assert ($workflow.Contains("'Integration.report_bundle_publication'")) '原生 All 失敗流程接入安全合成工件診斷'
