#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/test/ci_quality_summary.ps1')
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
$temp=Join-Path $env:TEMP ('ci_summary_timer_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
try {
 $file=Join-Path $temp 'success.md'
 Invoke-CIShardTimed -ShardIndex 2 -SummaryPath $file -Action { 'output' } | Out-Null
 $text=[IO.File]::ReadAllText($file)
 Assert ($text -match '分片 2' -and $text -match '分片量測階段耗時' -and $text -match 'success') '成功實際執行並記錄分片時間及狀態'
 $file=Join-Path $temp 'failure.md';$caught=''
 try {Invoke-CIShardTimed -ShardIndex 1 -SummaryPath $file -Action {throw 'fixture failure'}}catch{$caught=$_.Exception.Message}
 $text=[IO.File]::ReadAllText($file)
 Assert ($caught -eq 'fixture failure' -and $text -match 'failure' -and $text -match '未提供完整量測' -and $text -match '分片量測階段耗時') '拋錯時保留原例外並輸出失敗摘要'
 $file=Join-Path $temp 'native.md';$caught=''
 try {Invoke-CIShardTimed -ShardIndex 0 -SummaryPath $file -Action {& cmd.exe /d /c 'exit 7';if($LASTEXITCODE -ne 0){throw "native exit $LASTEXITCODE"}}}catch{$caught=$_.Exception.Message}
 Assert ($caught -eq 'native exit 7' -and $LASTEXITCODE -eq 7 -and ([IO.File]::ReadAllText($file) -match 'failure')) '非零原生退出與錯誤不得變成功'
 $caught='';try {Invoke-CIShardTimed -ShardIndex 0 -SummaryPath $temp -Action {throw 'original failure'}}catch{$caught=$_.Exception.Message}
 Assert ($caught -eq 'original failure') '摘要寫入失敗不得覆蓋原始失敗'
 $caught='';try {Invoke-CIShardTimed -ShardIndex 0 -SummaryPath $temp -Action {}}catch{$caught=$_.Exception.Message}
 Assert ($caught.Length -gt 0) '成功後摘要寫入失敗需明確失敗'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force}
