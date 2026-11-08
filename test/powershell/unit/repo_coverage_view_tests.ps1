#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/test/test_report.ps1')
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
$fixture=Join-Path $env:TEMP ('repo_coverage_view_'+[guid]::NewGuid().ToString('N'))
$checks=@(foreach($layer in @('Unit','Integration')){[pscustomobject]@{Name=$layer;Layer=$layer;Status='Passed';Executed=$true;Passed=$true;ExitCode=0;DurationSeconds=1;Assertions=@([pscustomobject]@{Name='real assertion';Passed=$true})}})
$c=[pscustomobject]@{SchemaVersion=1;Metric='complete-executable-lines-v1';Commit=('a'*40);RunUrl='https://github.com/example/repo/actions/runs/1';MeasuredAt='2026-11-08T00:00:00Z';SourceState='Clean';InventorySHA256=('b'*64);NormalizedSHA256=('c'*64);Result=[pscustomobject]@{SchemaVersion=1;Metric='complete-executable-lines-v1';Complete=$true;Covered=8;Executable=10;Percent=80.0;Missing=@();Blockers=@();Languages=[pscustomobject]@{Go=[pscustomobject]@{Covered=3;Executable=4};PowerShell=[pscustomobject]@{Covered=5;Executable=6}}}}
$r=Write-TestReports -Checks $checks -OutputDirectory $fixture -Commit $c.Commit -RunUrl $c.RunUrl -MeasuredAt $c.MeasuredAt -SourceState Clean -RefName main -RepoCoverage $c
Assert ($r.Coverage -ceq 'Measured' -and $r.RepoCoverage.Result.Covered -eq 8) '摘要保留整體共同計量原始計數'
foreach($file in @('index.html','summary.md','coverage.svg')){$text=[IO.File]::ReadAllText((Join-Path $fixture $file));Assert ($text.Contains('80.0%')) ('整體覆蓋率顯示真實合計：'+$file)}
$md=[IO.File]::ReadAllText((Join-Path $fixture 'summary.md'))
Assert ($md.Contains('Go') -and $md.Contains('3/4') -and $md.Contains('PowerShell') -and $md.Contains('5/6')) 'Actions文字摘要含語言分項原始計數'
. (Join-Path $root 'script/report/portal.ps1')
$replay=Join-Path $fixture 'replay'
Write-SnapshotView -Snapshot $r -OutputDirectory $replay
$replayed=Get-Content (Join-Path $replay 'summary.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert ($replayed.Coverage -ceq 'Measured' -and $replayed.RepoCoverage.Result.Covered -eq 8 -and ([IO.File]::ReadAllText((Join-Path $replay 'coverage.svg'))).Contains('80.0%')) '重繪與附加分項時保留既有整體覆蓋率身份計數和徽章'
$c.Result.Percent=99
$rejected=$false;try{Write-TestReports -Checks $checks -OutputDirectory (Join-Path $fixture 'wrong') -Commit $c.Commit -RunUrl $c.RunUrl -MeasuredAt $c.MeasuredAt -SourceState Clean -RepoCoverage $c|Out-Null}catch{$rejected=$true}
Assert $rejected '拒絕與原始計數不同的總率'
$c.Result.Percent=$null;$c.Result.Complete=$false;$c.Result.Missing=@('missing.ps1')
$r=Write-TestReports -Checks $checks -OutputDirectory (Join-Path $fixture 'incomplete') -Commit $c.Commit -RunUrl $c.RunUrl -MeasuredAt $c.MeasuredAt -SourceState Clean -RepoCoverage $c
Assert ($r.Coverage -ceq 'NotMeasured' -and -not([IO.File]::ReadAllText((Join-Path $fixture 'incomplete/coverage.svg')).Contains('80.0%'))) '缺來源不展示部分量測總率'
