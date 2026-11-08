#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/test/test_report.ps1')
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
function Refuse([scriptblock]$Action,[string]$Message){$rejected=$false;try{& $Action|Out-Null}catch{$rejected=$true};Assert $rejected $Message}
$fixture=Join-Path $env:TEMP ('report_scope_'+[guid]::NewGuid().ToString('N'))
$checks=@(foreach($layer in @('Unit','Integration')){[pscustomobject]@{Name=$layer;Layer=$layer;Status='Passed';Executed=$true;Passed=$true;ExitCode=0;DurationSeconds=1;Assertions=@([pscustomobject]@{Name='real assertion';Passed=$true})}})
$r=Write-TestReports -Checks $checks -OutputDirectory $fixture -Commit ('a'*40) -SourceState Clean -RefName main
Assert ($r.SchemaVersion -eq 2) '新測試報告使用不含實機占位的 schema 2'
Assert (-not(Test-Path (Join-Path $fixture 'system.svg'))) '新報告不產生 System 徽章'
foreach($file in @('index.html','summary.md','summary.json','junit.xml')){
 $content=[IO.File]::ReadAllText((Join-Path $fixture $file))
 Assert ($content -notmatch 'System|E2E|完整安裝|尚未實測|ComparisonStatus|FlakyStatus') ('新產物不顯示或保留取消的交付要求：'+$file)
}
Assert ($r.Success -and $r.Totals.SuitesExecuted -eq 2 -and $r.Totals.UnexecutedSuites -eq 0) '成功與分母只來自真正執行的測試'
$system=[pscustomobject]@{Name='System';Layer='System';Status='NotRun';Executed=$false;Passed=$null;ExitCode=$null;Assertions=@()}
Refuse {Write-TestReports -Checks @($checks+$system) -OutputDirectory (Join-Path $fixture 'invalid')} 'schema 2拒絕重新注入System占位'
$checks[0].Passed=$false;$checks[0].Status='Failed';$checks[0].ExitCode=1;$checks[0].Assertions[0].Passed=$false
$failed=Write-TestReports -Checks $checks -OutputDirectory (Join-Path $fixture 'failed')
Assert (-not $failed.Success -and $failed.Totals.AssertionsFailed -eq 1) '移除占位不會隱藏真失敗'
$legacy=Write-TestReports -SchemaVersion 1 -Checks @($checks+$system) -OutputDirectory (Join-Path $fixture 'legacy')
Assert-TestReportSnapshot $legacy
Assert ($legacy.SchemaVersion -eq 1 -and (Test-Path (Join-Path $fixture 'legacy/system.svg'))) '歷史schema 1可精確重建並驗證原始契約'