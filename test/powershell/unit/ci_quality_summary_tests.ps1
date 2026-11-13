#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/test/ci_quality_summary.ps1')
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
$report=[pscustomobject]@{Success=$false;Totals=[pscustomobject]@{AssertionsExecuted=10;AssertionsPassed=9;AssertionsFailed=1};RepoCoverage=[pscustomobject]@{Result=[pscustomobject]@{Complete=$true;Covered=9;Executable=10;Languages=[pscustomobject]@{go=[pscustomobject]@{Covered=1;Executable=2};powershell=[pscustomobject]@{Covered=8;Executable=8}}}};GoCoverage=[pscustomobject]@{Covered=8;TotalStatements=10;Percent=80}}
$text=New-CIQualitySummary -Report $report -AggregationState 'success'
Assert ($text -match '9/10' -and $text -match '失敗 1') '顯示測試斷言總數與失敗'
Assert ($text -match '90\.0%' -and $text -match '50\.0%' -and $text -match '100\.0%') '整體及各語言按各自分母計算'
Assert ($text -match 'statements' -and $text -match '80\.0%') 'Go statement 分項標明單位'
$failed=New-CIQualitySummary -Report $null -AggregationState 'failure'
Assert ($failed -match '失敗' -and $failed -match '未提供完整量測' -and $failed -notmatch '80\.0%') '失敗或資料缺失不假稱覆蓋率'
