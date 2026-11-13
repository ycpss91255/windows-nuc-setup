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
foreach($category in @('cleanup-process-active','cleanup-budget-exhausted','cleanup-output-incomplete','cleanup-operation-error')){
 $kind=Get-RunnerProbeNativeKind ([InvalidOperationException]::new('runner-'+$category))
 $names=@(Get-RunnerProbeDiagnostic -Phase 'probe' -HasPid $false -Message ('Docker readiness stage=probe category='+$category+' elapsed_ms=1 remaining_ms=999') -NativeKind $kind -NativeElapsedMilliseconds 1)
 Assert ($names -contains ('probe diagnostic category='+$category) -and $names -contains ('probe diagnostic native_kind='+$category)) ('fixture 診斷保留安全 cleanup 類別 '+$category)
}
$names=@(Get-RunnerProbeDiagnostic -Phase 'probe' -HasPid $true -Message 'private' -NativeKind 'private C:\secret' -NativeElapsedMilliseconds 123)
Assert ($names -contains 'probe diagnostic native_kind=unknown' -and $names -contains 'probe diagnostic native_elapsed_ms=123' -and ($names -join '|') -notmatch 'private|secret') '僅輸出受控分類與實際計時整數'
Assert ($null -ne (Get-Command Test-RunnerOwnedProbeExited -ErrorAction SilentlyContinue)) '獨立檢查唯一 owned probe 程序是否結束'
$probeName='owned_probe_'+[guid]::NewGuid().ToString('N')
$exe=Join-Path $env:TEMP ($probeName+'.exe')
$process=$null
try {
 Add-Type -OutputAssembly $exe -OutputType ConsoleApplication -TypeDefinition 'public class OwnedProbe { public static void Main(){ System.Threading.Thread.Sleep(60000); } }'
 $process=Start-Process -FilePath $exe -WindowStyle Hidden -PassThru
 Assert (-not (Test-RunnerOwnedProbeExited $probeName)) '真 owned 程序存活時不可宣稱結束'
 $process.Kill()
 Assert ($process.WaitForExit(5000)) '停止真 owned 程序'
 Assert (Test-RunnerOwnedProbeExited $probeName) '真 owned 程序結束後可確認'
} finally {
 if($process){if(-not $process.HasExited){$process.Kill();$null=$process.WaitForExit(5000)};$process.Dispose()}
 if(Test-Path -LiteralPath $exe){[IO.File]::Delete($exe)}
}
