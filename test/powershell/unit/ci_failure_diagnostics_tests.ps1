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
foreach($alias in @('INTEGRATION.REPORT_BUNDLE_PUBLICATION','Integration.Report_Bundle_Publication')){
 $caseOutput=@(Write-CIFailureDiagnostics -ReportDirectory $temp -SuiteNames @($alias)) -join "`n"
 Assert ($caseOutput.Contains('fixture_export:go_fixture_failed') -and -not $caseOutput.Contains('PRIVATE-CREDENTIAL-SENTINEL') -and -not $caseOutput.Contains('C:\Users') -and -not $caseOutput.Contains('unknown')) ('大小寫變體仍僅輸出固定安全代碼 '+$alias)
}
[IO.File]::WriteAllText((Join-Path $temp 'Integration.report_bundle_publication.log'),('x'*(4MB+1)))
$oversized=@(Write-CIFailureDiagnostics -ReportDirectory $temp -SuiteNames @('Integration.report_bundle_publication')) -join "`n"
Assert ($oversized.Contains('unavailable') -and $oversized.Length -lt 256) '大型私有日誌不讀取或公開'
$workflow=[IO.File]::ReadAllText((Join-Path $root '.github/workflows/windows_tests.yml'))
Assert ($workflow.Contains("'Integration.report_bundle_publication'")) '原生 All 失敗流程接入安全合成工件診斷'
$nested=Join-Path $temp 'nested.private.log'
$nestedSuite=Join-Path $temp 'Integration.ci_runner_coverage.log'
$valid='PowerShell worker failure diagnostic: {"SchemaVersion":1,"TestFile":"test/powershell/integration/ci_runner_tests.ps1","WorkerIndex":0,"Engine":"powershell","NativeExitCode":1,"CompletedAssertions":2,"FailedAssertionIndices":[2],"Locations":[],"ExceptionTypes":[]}'
[IO.File]::WriteAllLines($nested,[string[]]@('PRIVATE-SENTINEL C:\Users\hidden',$valid))
$record=Get-CINestedCoverageDiagnostic -Path $nested
Assert ($record -ceq '@@SAFE_NESTED_CI@@worker:2') '巢狀 worker 只輸出固定階段與失敗斷言序號'
[IO.File]::WriteAllText($nestedSuite,"PRIVATE-SENTINEL C:\Users\hidden`n$record")
$safe=@(Write-CIFailureDiagnostics -ReportDirectory $temp -SuiteNames @('Integration.ci_runner_coverage')) -join "`n"
Assert ($safe.Contains('worker:2') -and -not $safe.Contains('PRIVATE-SENTINEL') -and -not $safe.Contains('C:\Users')) 'CI 只公開精確固定診斷而非原始巢狀日誌'
foreach($bad in @('',($valid -replace '"WorkerIndex":0','"WorkerIndex":1'),($valid -replace '\[2\]','[999]'),($valid+"`n"+$valid),'@@SAFE_NESTED_CI@@worker:2')){
 [IO.File]::WriteAllText($nested,$bad)
 Assert ((Get-CINestedCoverageDiagnostic -Path $nested) -ceq '@@SAFE_NESTED_CI@@unavailable') '缺失、錯誤或重複記錄必須安全回 unavailable'
}
[IO.File]::WriteAllText($nested,('x'*(4MB+1)))
Assert ((Get-CINestedCoverageDiagnostic -Path $nested) -ceq '@@SAFE_NESTED_CI@@unavailable') '過大巢狀日誌不可公開'
[IO.File]::WriteAllText($nestedSuite,"@@SAFE_NESTED_CI@@worker:2`n@@SAFE_NESTED_CI@@worker:2`nPRIVATE-SENTINEL")
$safe=@(Write-CIFailureDiagnostics -ReportDirectory $temp -SuiteNames @('Integration.ci_runner_coverage')) -join "`n"
Assert ($safe.Contains('unavailable') -and -not $safe.Contains('worker:2') -and -not $safe.Contains('PRIVATE-SENTINEL')) '重複外層標記不可當成可信診斷'
Assert ($workflow.Contains("'Integration.ci_runner_coverage'")) '失敗 workflow 接入限型別巢狀診斷'
$wrapper=Join-Path $temp 'nested_wrapper.ps1';$capture=Join-Path $temp 'nested_wrapper.private.log'
$wrapperText=@'
function powershell.exe {
 Write-Output 'PRIVATE-SENTINEL C:\Users\hidden'
 Write-Output 'PowerShell worker failure diagnostic: {"SchemaVersion":1,"TestFile":"test/powershell/integration/ci_runner_tests.ps1","WorkerIndex":0,"Engine":"powershell","NativeExitCode":1,"CompletedAssertions":2,"FailedAssertionIndices":[2],"Locations":[],"ExceptionTypes":[]}'
 $global:LASTEXITCODE=1
}
try { & '__SUITE__'; exit 0 } catch { exit 1 }
'@
$wrapperText=$wrapperText.Replace('__SUITE__',(Join-Path $root 'test/powershell/integration/ci_runner_coverage_tests.ps1').Replace("'","''"))
[IO.File]::WriteAllText($wrapper,$wrapperText,[Text.UTF8Encoding]::new($true))
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $wrapper *> $capture
$nestedExit=$LASTEXITCODE
[IO.File]::Copy($capture,$nestedSuite,$true)
$safe=@(Write-CIFailureDiagnostics -ReportDirectory $temp -SuiteNames @('Integration.ci_runner_coverage')) -join "`n"
Assert ($nestedExit -eq 1 -and $safe.Contains('worker:2') -and -not $safe.Contains('PRIVATE-SENTINEL') -and -not $safe.Contains('C:\Users')) '真外層 suite 失敗保留非零退出並由 CI 安全顯示巢狀序號'
$invalidRecords=@(
 $valid.Replace('"SchemaVersion":1','"SchemaVersion":1,"Extra":"secret"'),
 $valid.Replace('"SchemaVersion":1','"SchemaVersion":9,"SchemaVersion":1'),
 $valid.Replace('"TestFile":"test/powershell/integration/ci_runner_tests.ps1"','"TestFile":["test/powershell/integration/ci_runner_tests.ps1"]'),
 $valid.Replace('"Engine":"powershell"','"Engine":["powershell"]'),
 $valid.Replace('"Locations":[]','"Locations":"secret"'),
 $valid.Replace('"ExceptionTypes":[]','"ExceptionTypes":"secret"'),
 $valid.Replace('"ExceptionTypes":[]','"ExceptionTypes":["secret"]'),
 $valid.Replace('"Locations":[]','"Locations":[{"File":"secret","Line":1}]'),
 $valid.Replace('"ExceptionTypes":[]','"ExceptionTypes":[],"PesterFailures":"secret"'),
 $valid.Replace('"ExceptionTypes":[]','"ExceptionTypes":[],"PesterFailures":[{"Phase":"secret","Type":"RuntimeException","File":"","Line":0}]'),
 $valid.Replace('"ExceptionTypes":[]','"ExceptionTypes":[],"FixtureStage":"fixture_export","FixtureReason":"go_fixture_failed"')
)
$acceptedInvalid=0
foreach($invalid in $invalidRecords){[IO.File]::WriteAllText($nested,$invalid);if((Get-CINestedCoverageDiagnostic -Path $nested) -cne '@@SAFE_NESTED_CI@@unavailable'){$acceptedInvalid++}}
Assert ($acceptedInvalid -eq 0) '嚴格拒絕額外重複欄位、錯誤陣列與不符該 suite 的可選診斷'
