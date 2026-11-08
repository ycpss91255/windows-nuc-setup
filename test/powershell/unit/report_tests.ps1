#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
. (Join-Path $root 'script/test/test_report.ps1')
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
$fixture=Join-Path $env:TEMP ('windows_report_'+[guid]::NewGuid().ToString('N'))
$checks=@(
 [pscustomobject]@{Name='unit';Layer='Unit';Status='Passed';Executed=$true;Passed=$true;ExitCode=0;DurationSeconds=1;Assertions=@([pscustomobject]@{Name='a < b & c';Passed=$true})},
 [pscustomobject]@{Name='integration';Layer='Integration';Status='Failed';Executed=$true;Passed=$false;ExitCode=1;DurationSeconds=2;Assertions=@([pscustomobject]@{Name='file C:\Users\secret\private';Passed=$false})},
 [pscustomobject]@{Name='system';Layer='System';Status='NotRun';Executed=$false;Passed=$null;Assertions=@()}
)
$r=Write-TestReports -Checks $checks -OutputDirectory $fixture -Commit ('a'*40)
Assert (-not $r.Success -and $r.Coverage -eq 'NotMeasured') '真失敗不標成功，未量測不捏造覆蓋率'
[xml]$junit=Get-Content (Join-Path $fixture 'junit.xml') -Raw -Encoding UTF8
Assert ($junit.SelectNodes('//failure').Count -eq 1 -and $junit.SelectNodes('//skipped').Count -eq 1) 'JUnit 分開失敗與未執行'
$html=Get-Content (Join-Path $fixture 'index.html') -Raw -Encoding UTF8
Assert ($html.Contains('a &lt; b &amp; c') -and -not $html.Contains('secret')) 'HTML 編碼且不公開本機路徑'
Assert ((Get-Content (Join-Path $fixture 'unit.svg') -Raw -Encoding UTF8).Contains('passed') -and (Get-Content (Join-Path $fixture 'integration.svg') -Raw -Encoding UTF8).Contains('failed')) '分層徽章來自實際結果'
Assert ((Get-Content (Join-Path $fixture 'system.svg') -Raw -Encoding UTF8).Contains('not run')) 'System 徽章不偽裝為通過'
$crash=[pscustomobject]@{Name='crash';Layer='Unit';Status='Failed';Executed=$true;Passed=$false;ExitCode=1;Assertions=@([pscustomobject]@{Name='earlier success';Passed=$true})}
$null=Write-TestReports -Checks @($crash) -Layer Unit -OutputDirectory (Join-Path $fixture 'crash')
[xml]$junit=Get-Content (Join-Path $fixture 'crash/junit.xml') -Raw -Encoding UTF8
Assert ($junit.SelectNodes('//failure').Count -eq 1) '前面斷言成功後程序崩潰仍產生失敗項'
function Refuse([scriptblock]$Action,[string]$Name){$caught=$false;try{& $Action|Out-Null}catch{$caught=$true};Assert $caught $Name}
Refuse {Write-TestReports -Checks @($checks[2]) -OutputDirectory (Join-Path $fixture 'notrun')} '全部未執行不會變成成功報表'
Refuse {Write-TestReports -Checks @($checks[0]) -OutputDirectory (Join-Path $fixture 'partial')} 'All 缺整合層即拒絕'
$contradiction=$r|ConvertTo-Json -Depth 10|ConvertFrom-Json
$contradiction.Checks[0].Executed=$false
Refuse {Assert-TestReportSnapshot $contradiction} '執行狀態矛盾被拒絕'
$contradiction=$r|ConvertTo-Json -Depth 10|ConvertFrom-Json
$contradiction.Totals.AssertionsPassed=999
Refuse {Assert-TestReportSnapshot $contradiction} '統計與斷言不符被拒絕'
$contradiction=$r|ConvertTo-Json -Depth 10|ConvertFrom-Json
$contradiction.Checks[0].ExitCode=1
Refuse {Assert-TestReportSnapshot $contradiction} '退出碼與成功不符被拒絕'
$passChecks=$checks|ConvertTo-Json -Depth 8|ConvertFrom-Json
$passChecks[1].Status='Passed';$passChecks[1].Passed=$true;$passChecks[1].ExitCode=0;$passChecks[1].Assertions[0].Passed=$true
$release=Write-TestReports -Checks $passChecks -OutputDirectory (Join-Path $fixture 'release') -Version v1.2.3 -RefType Release -RefName v1.2.3 -Commit ('a'*40) -RunUrl 'https://github.com/example/repo/actions/runs/1' -SourceState Clean -Environment 'Windows PowerShell 5.1' -MeasuredAt '2026-11-08T00:00:00.0000000Z' -Changes @('修正範例')
Assert-TestReportSnapshot $release -Release
Assert ($release.Version -eq 'v1.2.3') '乾淨完整的版本證據可驗證'
$release.SourceState='Dirty'
Refuse {Assert-TestReportSnapshot $release -Release} 'Dirty 版本快照拒絕發布'
$release.SourceState='Clean'
$null=Write-TestReports -Checks $release.Checks -OutputDirectory (Join-Path $fixture 'replay') -Layer $release.RequestedLayer -Version $release.Version -RefType $release.RefType -RefName $release.RefName -Commit $release.Commit -RunUrl $release.RunUrl -SourceState $release.SourceState -Environment $release.Environment -MeasuredAt $release.MeasuredAt -Changes $release.Changes
$equal=$true
foreach($file in Get-ChildItem (Join-Path $fixture 'release') -File){if((Get-FileHash $file.FullName).Hash -ne (Get-FileHash (Join-Path (Join-Path $fixture 'replay') $file.Name)).Hash){$equal=$false}}
Assert $equal '同一版本 JSON 重建所有公開檔案位元組一致且保留量測時間'
$contradiction=$r|ConvertTo-Json -Depth 10|ConvertFrom-Json
$contradiction.Checks[0].Passed=1
Refuse {Assert-TestReportSnapshot $contradiction} '不把整數或 null 默認轉成成功布林值'
$contradiction=$r|ConvertTo-Json -Depth 10|ConvertFrom-Json
$contradiction.Checks[2].Assertions=@([pscustomobject]@{Name='not executed';Passed=$true})
Refuse {Assert-TestReportSnapshot $contradiction} 'NotRun 不得攜帶斷言污染執行總數'
$privateOutput=Join-Path $fixture 'private_metadata'
$null=Write-TestReports -Checks $checks -OutputDirectory $privateOutput -Version 'C:\Users\secret\version' -Environment 'C:\Users\secret\environment' -RefName 'C:\Users\secret\branch' -Changes @('C:\Users\secret\change')
$leaked=@(Get-ChildItem $privateOutput -File|Where-Object {(Get-Content $_.FullName -Raw -Encoding UTF8).Contains('secret')})
Assert ($leaked.Count -eq 0) '所有公開格式的版本環境分支與變更均去識別'
Write-Host ('Report preview: '+(Join-Path $fixture 'release/index.html'))
$badgeWidths=@()
foreach($name in @('unit','integration','system','coverage')){
 [xml]$badge=Get-Content (Join-Path $fixture ($name+'.svg')) -Raw -Encoding UTF8
 $rects=if($name -eq 'coverage'){@($badge.svg.g[0].rect)}else{@($badge.svg.rect)}
 $font=if($name -eq 'coverage'){$badge.svg.g[1].'font-size'}else{$badge.svg.g.'font-size'}
 $badgeWidths+=[int]$badge.svg.width
 Assert ($badge.svg.height -eq '20' -and $font -eq '11' -and $rects[0].fill -eq '#555') ('徽章保留一致字體與高度：'+$name)
 Assert ([int]$badge.svg.width -eq ([int]$rects[0].width+[int]$rects[1].width) -and $badge.svg.'aria-label'.Contains('branch')) ('徽章寬度符合兩段文字且保留範圍：'+$name)
}
Assert (@($badgeWidths|Select-Object -Unique).Count -gt 1 -and ($badgeWidths|Measure-Object -Maximum).Maximum -lt 360) '不同文字使用自適應寬度而非固定寬度大色塊'
[xml]$passedBadge=Get-Content (Join-Path $fixture 'unit.svg') -Raw -Encoding UTF8
[xml]$failedBadge=Get-Content (Join-Path $fixture 'integration.svg') -Raw -Encoding UTF8
Assert ($passedBadge.svg.rect[1].fill -eq '#4c1' -and $failedBadge.svg.rect[1].fill -eq '#e05d44') '通過與失敗使用 base 色階且保留原測試狀態'
[xml]$coverageBadge=Get-Content (Join-Path $fixture 'coverage.svg') -Raw -Encoding UTF8
Assert ($coverageBadge.svg.g[0].rect[1].fill -eq '#9f9f9f' -and $coverageBadge.svg.'aria-label'.Contains('not measured') -and -not $coverageBadge.svg.'aria-label'.Contains('%')) 'Coverage 未量測使用中性灰色而非假百分比'

Assert ($html.Contains('archive/'+('a'*40)+'.zip') -and -not $html.Contains('href="https://github.com/ycpss91255/windows_setup/releases"')) '分支報告下載指向本次提交，不導向舊發布版'
Assert ($html.Contains('完整 Windows 安裝、重開機與真實硬體設定尚未實測') -and $html.Contains('blob/main/readme.md')) '明細首屏保留未實測界限與目前使用步驟'

$changeOutput=Join-Path $fixture 'maintenance_changes'
$changeReport=Write-TestReports -Checks $checks -OutputDirectory $changeOutput -Changes @('版本比較缺證據時明示 Unknown')
$changeHtml=Get-Content (Join-Path $changeOutput 'index.html') -Raw -Encoding UTF8
Assert ($changeReport.Changes[0].Contains('Unknown') -and $changeHtml -match '(?s)<details><summary>本次維護變更摘要</summary>.*?Unknown.*?</details>') '維護術語只在折疊摘要呈現，原始變更證據保持不變'
