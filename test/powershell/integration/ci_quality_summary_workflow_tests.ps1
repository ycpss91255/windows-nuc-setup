#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
$workflow=[IO.File]::ReadAllText((Join-Path $root '.github/workflows/windows_tests.yml'))
Assert ($workflow -match '(?m)^  pull_request:\s*$' -and $workflow -match '(?m)^    branches: \[main\]\s*$') 'workflow 由 PR 與 main 觸發'
$aggregation=[regex]::Match($workflow,'(?ms)^  coverage-aggregation:\s*\r?\n(.*?)(?=^  requirements-gate:)').Groups[1].Value
Assert ($aggregation -match 'needs: \[isolated-tests, powershell-coverage\]' -and $aggregation -match 'run_repo_coverage\.ps1' -and $aggregation -match 'New-CIQualitySummary -Report \$report -AggregationState ''success''' -and $aggregation -notmatch '(?m)^    if:') 'PR 與 main 共用聚合且驗證完成才輸出摘要'
$rollup=[regex]::Match($workflow,'(?ms)^  ci-rollup:[^\S\r\n]*\r?\n(.*?)(?=^  [a-z][a-z0-9-]*:[^\S\r\n]*$)').Groups[1].Value
Assert ($rollup -match 'if: always\(\)' -and $rollup -match 'needs: \[isolated-tests, requirements-gate, docker-tests, oobe_payload_inspection, powershell-coverage, coverage-aggregation\]') 'rollup 在失敗時仍取得必要工作的狀態'
$step=[regex]::Match($rollup,'(?m)^      - name: 確認全部必要測試成功[^\S\r\n]*\r?\n(?s:.*?)^        run: \|[^\S\r\n]*\r?\n((?:^          [^\r\n]*\r?\n)+)').Groups[1].Value
Assert ([bool]$step) '擷取實際 rollup 步驟'
Assert ($rollup -notmatch '(?m)^  cache-diagnostic-' -and $step -notmatch '(?m)^  cache-diagnostic-') 'rollup 與擷取的 PowerShell 區塊不得包含後續獨立診斷 job'
$script=[scriptblock]::Create(($step -replace '(?m)^          ',''))
$temp=Join-Path $env:TEMP ('ci_summary_rollup_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
try {
 $env:GITHUB_STEP_SUMMARY=Join-Path $temp 'summary.md'
 foreach($name in @('TEST_RESULT','REQUIREMENTS_RESULT','DOCKER_RESULT','OOBE_PAYLOAD_RESULT','POWERSHELL_COVERAGE_RESULT')){[Environment]::SetEnvironmentVariable($name,'success','Process')}
 $env:COVERAGE_RESULT='failure';$caught=$false
 Push-Location $root;try{try{& $script}catch{$caught=$true}}finally{Pop-Location}
 $text=[IO.File]::ReadAllText($env:GITHUB_STEP_SUMMARY)
 Assert ($caught -and $text -match 'Coverage: failure' -and $text -match '未提供完整量測' -and $text -notmatch '\d+\.\d+%') '實際 rollup 失敗時明示未完整量測且保留失敗'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force}
