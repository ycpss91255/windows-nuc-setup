#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/test/test_report.ps1')
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
$fixture=Join-Path $env:TEMP ('simple_portal_'+[guid]::NewGuid().ToString('N'))
$checks=@(foreach($layer in @('Unit','Integration')){[pscustomobject]@{Name=$layer;Layer=$layer;Status='Passed';Executed=$true;Passed=$true;ExitCode=0;DurationSeconds=1;Assertions=@([pscustomobject]@{Name='real assertion';Passed=$true})}})
Write-TestReports -Checks $checks -OutputDirectory (Join-Path $fixture 'input') -Commit ('a'*40) -SourceState Clean -RefName main -Environment Test -RunUrl 'https://github.com/ycpss91255/windows_setup/actions/runs/123' |Out-Null
$catalog=Join-Path $fixture 'catalog.json';[IO.File]::WriteAllText($catalog,'[]')
& (Join-Path $root 'script/report/build_portal.ps1') -CatalogPath $catalog -OutputDirectory (Join-Path $fixture 'public') -MainSnapshotPath (Join-Path $fixture 'input/summary.json')|Out-Null
$page=[IO.File]::ReadAllText((Join-Path $fixture 'public/index.html'))
Assert ($page -notmatch '完整安裝|尚未實測|比較兩個版本|compare.js|Unknown') '簡潔首頁不顯示已取消的實機要求與比較面板'
Assert (-not(Test-Path (Join-Path $fixture 'public/compare.js')) -and -not(Test-Path (Join-Path $fixture 'public/comparisons'))) '不生成版本比較程式與資料'
Assert ($page -match '目前程式檢查通過' -and $page -match 'aaaaaaa' -and $page -match 'UTC' -and $page -match 'main/index.html' -and $page -match 'readme.md') '首頁保留可核對結論來源時間與操作入口'
Assert ($page -match '整體覆蓋率' -and $page -notmatch 'Go 程式敘述覆蓋率') '首頁整體覆蓋率不以語言分項冒充'

& (Join-Path $root 'script/test/create_portal_fixture.ps1') -OutputDirectory (Join-Path $fixture 'synthetic')
$sample=Get-Content (Join-Path $fixture 'synthetic/synthetic_snapshot/summary.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert ($sample.SchemaVersion -eq 2 -and @($sample.Checks|Where-Object Layer -Like 'System*').Count -eq 0) '本機合成驗證樣本使用新報告契約'