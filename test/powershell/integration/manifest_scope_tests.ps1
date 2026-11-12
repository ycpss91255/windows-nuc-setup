#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/test/test_report.ps1')
. (Join-Path $root 'script/report/portal.ps1')
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
$old=@(Get-TestReportArtifactNames 1)
$current=@(Get-TestReportArtifactNames 2)
Assert ($old.Count -eq 8 -and $old -contains 'system.svg' -and $old -notcontains 'coverage.xml') '舊manifest保持精確8檔契約'
Assert ($current.Count -eq 10 -and $current -notcontains 'system.svg' -and $current -contains 'repo_coverage.json' -and $current -contains 'coverage_inventory.json' -and $current -contains 'coverage.xml') '新manifest精確包含總覆蓋率三證據並移除System'
$fixture=Join-Path $env:TEMP ('manifest_scope_'+[guid]::NewGuid().ToString('N'))
$checks=@(foreach($layer in @('Unit','Integration')){[pscustomobject]@{Name=$layer;Layer=$layer;Status='Passed';Executed=$true;Passed=$true;ExitCode=0;DurationSeconds=1;Assertions=@([pscustomobject]@{Name='real assertion';Passed=$true})}})
Write-TestReports -Checks $checks -OutputDirectory $fixture -Commit ('a'*40) -SourceState Clean -RefType Release -RefName v1.0.0 -Version v1.0.0 -Environment Test -RunUrl 'https://github.com/example/repo/actions/runs/123'|Out-Null
$script:called=$false
function gh {$script:called=$true;throw 'must never call remote'}
Assert ((Get-Command gh).CommandType -eq 'Function') '發佈範圍負例必須使用 mock gh'
$rejected=$false
try{& (Join-Path $root 'script/report/publish_quality_release.ps1') -PublicDirectory $fixture -Version v1.0.0 -Commit ('a'*40) -NotesPath (Join-Path $fixture 'summary.md') -Repository example/repo}catch{$rejected=$true}
Assert ($rejected -and -not $script:called) '新Release缺完整總覆蓋率證據在任何遠端操作前拒絕'
Remove-Item Function:\gh
