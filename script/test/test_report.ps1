#Requires -Version 5.1
. (Join-Path $PSScriptRoot 'go_coverage.ps1')
function Protect-ReportText([string]$Text){
 foreach($value in @($env:USERPROFILE,$env:TEMP,$env:TMP,$env:GITHUB_WORKSPACE)|Where-Object {$_}){$Text=$Text.Replace($value,'[local]')}
 $Text=[regex]::Replace($Text,'(?i)[A-Z]:[\\/][^\r\n|]*','[local path]')
 return $Text.Replace("`r",' ').Replace("`n",' ')
}
function Assert-TestReportSnapshot {
 param([Parameter(Mandatory=$true)]$Report,[switch]$Release)
 foreach($key in @('SchemaVersion','Version','Commit','RequestedLayer','MeasuredAt','SourceState','RefType','RefName','Environment','Checks','Success','Coverage','ComparisonStatus','FlakyStatus','Changes','Totals','RunUrl')){if($key -notin $Report.PSObject.Properties.Name){throw ('報表缺少必要欄位：'+$key)}}
 if($Report.SchemaVersion -ne 1 -or $Report.RequestedLayer -notin @('All','Unit','Integration') -or $Report.SourceState -notin @('Clean','Dirty','Unknown') -or $Report.RefType -notin @('Branch','Release') -or $Report.Coverage -ne 'NotMeasured' -or $Report.ComparisonStatus -ne 'Unknown' -or $Report.FlakyStatus -ne 'Unknown'){throw '不支援的報表結構或範圍。'}
 $stamp=[DateTimeOffset]::MinValue
 if(-not [DateTimeOffset]::TryParse([string]$Report.MeasuredAt,[ref]$stamp)){throw '報表量測時間不合法。'}
 if(-not @($Report.Checks).Count -or $Report.Success -isnot [bool]){throw '報表沒有有效測試結果。'}
 if($Report.RequestedLayer -eq 'All'){foreach($layer in @('Unit','Integration')){if(-not @($Report.Checks|Where-Object {$_.Layer -eq $layer -and $_.Executed}).Count){throw ('完整範圍缺少已執行層級：'+$layer)}}}
 if(@($Report.Checks.Name|Select-Object -Unique).Count -ne @($Report.Checks).Count){throw '報表測試識別重複。'}
 if($Report.RequestedLayer -ne 'All' -and -not @($Report.Checks|Where-Object {$_.Layer -eq $Report.RequestedLayer -and $_.Executed}).Count){throw '所選層級未執行，不能宣稱通過。'}
 foreach($check in $Report.Checks){
  if($check.Executed -and $check.Passed -isnot [bool]){throw '通過欄位必須是布林值，不能由 null 或字串轉換。'}
  if($check.Executed -and ($check.ExitCode -isnot [int] -and $check.ExitCode -isnot [long])){throw '已執行項目缺少整數退出碼。'}
  if(($check.Status -eq 'Passed' -and $check.ExitCode -ne 0) -or ($check.Status -eq 'Failed' -and $check.ExitCode -eq 0) -or ($check.Status -eq 'NotRun' -and $null -ne $check.ExitCode)){throw '退出碼與狀態矛盾。'}
  if($check.Name -isnot [string] -or $check.Layer -notin @('Static','Unit','Integration','System','System E2E') -or $check.Status -notin @('Passed','Failed','NotRun') -or $check.Executed -isnot [bool]){throw '報表測試狀態格式錯誤。'}
  if(($check.Status -eq 'Passed' -and (-not $check.Executed -or $check.Passed -cne $true)) -or ($check.Status -eq 'Failed' -and (-not $check.Executed -or $check.Passed -cne $false)) -or ($check.Status -eq 'NotRun' -and ($check.Executed -or $null -ne $check.Passed))){throw '報表執行與通過狀態矛盾。'}
  if($check.Layer -like 'System*' -and $check.Status -ne 'NotRun'){throw '此報表格式不接受未實作的 System 成功聲明。'}
  if($check.Status -eq 'NotRun' -and @($check.Assertions).Count){throw '未執行項目不得攜帶已執行斷言。'}
  foreach($assertion in @($check.Assertions)){if($assertion.Name -isnot [string] -or $assertion.Passed -isnot [bool]){throw '斷言資料不合法。'}}
  if($check.Status -eq 'Passed' -and $check.Layer -in @('Unit','Integration') -and (-not @($check.Assertions).Count -or @($check.Assertions|Where-Object {-not $_.Passed}).Count)){throw '通過的測試缺少完整成功斷言。'}
 }
 if($Report.PSObject.Properties['GoCoverage']){Assert-GoCoverage -Coverage $Report.GoCoverage -Report $Report}
 $allAssertions=@($Report.Checks|ForEach-Object {$_.Assertions})
 $expected=@{SuitesExecuted=@($Report.Checks|Where-Object Executed).Count;AssertionsExecuted=$allAssertions.Count;AssertionsPassed=@($allAssertions|Where-Object Passed).Count;AssertionsFailed=@($allAssertions|Where-Object {-not $_.Passed}).Count;UnexecutedSuites=@($Report.Checks|Where-Object {-not $_.Executed}).Count}
 foreach($key in $expected.Keys){if($key -notin $Report.Totals.PSObject.Properties.Name -or $Report.Totals.$key -ne $expected[$key]){throw ('報表統計不一致：'+$key)}}
 $success=@($Report.Checks|Where-Object {$_.Executed -and -not $_.Passed}).Count -eq 0
 if($Report.Success -cne $success){throw '報表總結果與細項不一致。'}
 if($Release -or $Report.RefType -eq 'Release'){
  if($Report.Version -cnotmatch '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-rc[1-9][0-9]*)?$' -or $Report.RefName -cne $Report.Version -or $Report.Commit -notmatch '^[a-fA-F0-9]{40}$' -or $Report.SourceState -ne 'Clean' -or $Report.RequestedLayer -ne 'All' -or $Report.Environment -eq 'Unknown' -or -not $Report.Success -or $Report.RunUrl -notmatch '^https://github.com/[^/]+/[^/]+/actions/runs/[0-9]+$'){throw '版本快照缺少乾淨來源、完整成功測試或提交執行身分。'}
 }
}
function Write-TestReports {
 param([Parameter(Mandatory=$true)][object[]]$Checks,[Parameter(Mandatory=$true)][string]$OutputDirectory,[string]$Layer='All',[string]$Commit=$env:GITHUB_SHA,[string]$RunUrl,[ValidateSet('Clean','Dirty','Unknown')][string]$SourceState='Unknown',[string]$Version='Unknown',[string]$Environment='Unknown',[ValidateSet('Branch','Release')][string]$RefType='Branch',[string]$RefName='Unknown',[string]$MeasuredAt=([DateTime]::UtcNow.ToString('o')),[string[]]$Changes=@(),$GoCoverage)
 $encoding=New-Object Text.UTF8Encoding($false)
 New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
 $safe=@(foreach($check in $Checks){
  $assertions=@(foreach($item in @($check.Assertions)){if($null -ne $item){[pscustomobject]@{Name=(Protect-ReportText $item.Name);Passed=$item.Passed}}})
  [pscustomobject]@{Name=(Protect-ReportText $check.Name);Layer=$check.Layer;Status=$check.Status;Executed=$check.Executed;Passed=$check.Passed;ExitCode=$check.ExitCode;DurationSeconds=[double]$check.DurationSeconds;Assertions=$assertions}
 })
 $ok=@($safe|Where-Object {$_.Executed -and -not $_.Passed}).Count -eq 0
 $report=[ordered]@{SchemaVersion=1;Version=(Protect-ReportText $Version);Environment=(Protect-ReportText $Environment);RefType=$RefType;RefName=(Protect-ReportText $RefName);MeasuredAt=$MeasuredAt;Changes=@($Changes|Select-Object -First 20|ForEach-Object {Protect-ReportText $_});ComparisonStatus='Unknown';FlakyStatus='Unknown';Success=$ok;Scope='Unit and isolated integration; system/E2E deferred, coverage not measured';RequestedLayer=$Layer;SourceState=$SourceState;Commit=$(if($Commit -match '^[a-fA-F0-9]{40}$'){$Commit}else{'local-unversioned'});RunUrl=$(if($RunUrl -match '^https://github.com/[^/]+/[^/]+/actions/runs/[0-9]+$'){$RunUrl}else{''});GeneratedAt=$MeasuredAt;Coverage='NotMeasured';Checks=$safe}
 if($null -ne $GoCoverage){$report.GoCoverage=$GoCoverage;$report.Scope='Unit and isolated integration; system/E2E deferred; PowerShell coverage not measured; Go statement coverage measured separately'}
 $allAssertions=@($safe|ForEach-Object {$_.Assertions})
 $report.Totals=[pscustomobject]@{SuitesExecuted=@($safe|Where-Object Executed).Count;AssertionsExecuted=$allAssertions.Count;AssertionsPassed=@($allAssertions|Where-Object Passed).Count;AssertionsFailed=@($allAssertions|Where-Object {-not $_.Passed}).Count;UnexecutedSuites=@($safe|Where-Object {-not $_.Executed}).Count}
 Assert-TestReportSnapshot -Report ([pscustomobject]$report)
 $Version=$report.Version;$RefName=$report.RefName;$Environment=$report.Environment;$Changes=$report.Changes
 [IO.File]::WriteAllText((Join-Path $OutputDirectory 'summary.json'),($report|ConvertTo-Json -Depth 8),$encoding)
 $md=@('# Windows 測試報表','','僅單元與隔離整合測試；System／完整 E2E 暫緩且未執行。程式碼覆蓋率未量測。','','| 層級 | 測試套件 | 狀態 | 斷言通過／實際執行 | 秒 |','| --- | --- | --- | --- | --- |')
 foreach($check in $safe){$passed=@($check.Assertions|Where-Object Passed).Count;$md+='| '+$check.Layer+' | '+$check.Name.Replace('|','/')+' | '+$check.Status+' | '+$passed+'/'+$check.Assertions.Count+' | '+$check.DurationSeconds+' |'}
 $md+=@('','Version: '+$Version+' / '+$RefType+' '+$RefName+' / Commit: '+$report.Commit+' / source: '+$SourceState+' / TestScope: '+$Layer+' / MeasuredAt: '+$MeasuredAt+' / Environment: '+$report.Environment,'')
 if($null -ne $GoCoverage){$md[2]=$md[2].Replace('程式碼覆蓋率未量測。','PowerShell 覆蓋率未量測。');$md+=@('','Go 程式敘述覆蓋率：'+(Get-GoCoveragePercentText $GoCoverage)+'；範圍為全部自有 Go 工具（含 CLI），不含 PowerShell 或第三方程式。','Go statements: '+$GoCoverage.CoveredStatements+'/'+$GoCoverage.TotalStatements+'；門檻 '+$GoCoverage.Threshold+'%')}
 [IO.File]::WriteAllText((Join-Path $OutputDirectory 'summary.md'),($md -join "`n"),$encoding)
 $conclusion=if(-not $ok){'本次測試未通過'}elseif($Layer -ne 'All'){'僅所選層級通過，未執行的層級沒有結論'}else{'單元與隔離整合測試通過；完整安裝尚未驗證'}
 $body='<h1>Windows 設定工具｜本次檢查明細</h1><h2>'+[Net.WebUtility]::HtmlEncode($conclusion)+'</h2><p>檢查範圍是程式邏輯，以及隔離環境中的模組配合；完整 Windows 安裝、重開機與真實硬體設定尚未實測。</p><p><a href="https://github.com/ycpss91255/windows_setup/blob/main/readme.md">查看 USB 安裝與使用步驟</a></p>'
 $scopeText=if($RefType -eq 'Release'){'已發布版本 '+$Version}else{'目前分支 '+$RefName+' 的程式檢查，不是舊發布版本的測試結果'}
 $body+='<p><strong>'+[Net.WebUtility]::HtmlEncode($scopeText)+'</strong><br>程式提交：'+[Net.WebUtility]::HtmlEncode($report.Commit.Substring(0,[Math]::Min(7,$report.Commit.Length)))+' · 檢查時間（UTC）：'+[Net.WebUtility]::HtmlEncode($MeasuredAt)+'</p><p>此工具提供 Windows 初始化與設定；GitHub 下載是來源包，需另備 Autologon，驅動包可選且僅支援對應 NUC 機型。</p>'
 if($RefType -eq 'Release'){$body+='<p><a href="https://github.com/ycpss91255/windows_setup/releases/tag/'+$Version+'">此版本 Release 說明與附件</a> · <a href="https://github.com/ycpss91255/windows_setup/archive/refs/tags/'+$Version+'.zip">下載此版本原始碼 ZIP（非完整安裝包）</a></p>'}
 if($RefType -ne 'Release' -and $report.Commit -match '^[a-fA-F0-9]{40}$'){$body+='<p><a href="https://github.com/ycpss91255/windows_setup/archive/'+$report.Commit+'.zip">下載本次提交原始碼（需另備工具）</a>：不含 Autologon 或獨立驅動包。</p>'}
 $body+='<p><a href="summary.json">完整 JSON 證據</a> · <a href="junit.xml">JUnit 結果</a> · <a href="summary.md">文字摘要</a></p>'
 $body+='<details><summary>技術資訊與來源提交</summary><dl><dt>程式版本宣告值（分支報告不代表同名發布版已驗證）</dt><dd>'+[Net.WebUtility]::HtmlEncode($Version)+'</dd><dt>來源提交（Commit）</dt><dd>'+[Net.WebUtility]::HtmlEncode($report.Commit)+'</dd><dt>測試範圍</dt><dd>'+[Net.WebUtility]::HtmlEncode($Layer)+' · Unit / Integration</dd><dt>檢查時間（UTC）</dt><dd>'+[Net.WebUtility]::HtmlEncode($MeasuredAt)+'</dd><dt>環境與來源狀態</dt><dd>'+[Net.WebUtility]::HtmlEncode($Environment+' / '+$SourceState)+'</dd></dl></details>'
 if($report.RunUrl){$body+='<p><a href="'+$report.RunUrl+'">此提交的 GitHub Actions 執行紀錄</a></p>'}
 $body+='<details><summary>本次維護變更摘要</summary><ul>';if(@($Changes).Count){foreach($change in $report.Changes){$body+='<li>'+[Net.WebUtility]::HtmlEncode($change)+'</li>'}}else{$body+='<li>目前沒有這個版本的變更摘要。</li>'};$body+='</ul></details>'
 $body+='<h2>尚未驗證的部分</h2><ul><li>完整安裝：尚未在全新 Windows 上走完初始化、套用設定與重開機驗收。</li><li>程式碼覆蓋率：尚未量測，沒有可提供的百分比。</li><li>版本差異與測試穩定性：尚無足夠紀錄可判斷，不代表沒有退步或不穩定情況。</li><li>這份報告不代表已在你的電腦完成安裝。</li></ul><h2>各項檢查結果</h2>'
 foreach($check in $safe){$body+='<details><summary>'+[Net.WebUtility]::HtmlEncode($check.Layer+' · '+$check.Name+' · '+$check.Status)+'</summary><p>'+[Net.WebUtility]::HtmlEncode([string]$check.DurationSeconds)+' 秒</p><ul>';foreach($assertion in $check.Assertions){$body+='<li>'+$(if($assertion.Passed){'PASS'}else{'FAIL'})+' · '+[Net.WebUtility]::HtmlEncode($assertion.Name)+'</li>'};$body+='</ul></details>'}
 if($null -ne $GoCoverage){
  $body=$body.Replace('程式碼覆蓋率：尚未量測，沒有可提供的百分比。','PowerShell 覆蓋率：尚未量測；Go 工具另列量測數值。')
  $body+='<h2>Go 程式敘述覆蓋率</h2><p><strong>'+(Get-GoCoveragePercentText $GoCoverage)+'</strong> · '+$GoCoverage.CoveredStatements+'/'+$GoCoverage.TotalStatements+' statements；門檻 '+$GoCoverage.Threshold+'%。範圍為全部自有 Go 工具（含 CLI），不含 PowerShell 或第三方程式。</p><p><a href="go_coverage.json">Go 量測資料</a> · <a href="go_coverage.out">原始 Go 覆蓋率</a></p>'
  Write-GoCoverageView -Coverage $GoCoverage -RefType $RefType -OutputDirectory $OutputDirectory
 }
 $html='<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Windows 測試報表</title><style>body{font:16px system-ui;max-width:1100px;margin:32px auto;padding:0 20px;color:#17202a;background:#f7f9fb}details{background:white;padding:16px;margin:16px 0;border:1px solid #dde3ea;border-radius:8px}li{margin:5px 0}</style><body>'+$body+'</body></html>'
 [IO.File]::WriteAllText((Join-Path $OutputDirectory 'index.html'),$html,$encoding)
 $xml=New-Object Xml.XmlDocument;$tests=$xml.CreateElement('testsuites');[void]$xml.AppendChild($tests)
 foreach($check in $safe){
  $suite=$xml.CreateElement('testsuite');$suite.SetAttribute('name',$check.Name);$suite.SetAttribute('time',[string]$check.DurationSeconds);[void]$tests.AppendChild($suite)
  $items=@($check.Assertions);if(-not $items.Count){$items=@([pscustomobject]@{Name=$check.Name;Passed=$check.Passed})}
  if($check.Executed -and -not $check.Passed -and @($items|Where-Object {-not $_.Passed}).Count -eq 0){$items+=@([pscustomobject]@{Name='套件執行／報表儀器失敗';Passed=$false})}
  foreach($item in $items){$case=$xml.CreateElement('testcase');$case.SetAttribute('name',$item.Name);$case.SetAttribute('classname',$check.Layer);[void]$suite.AppendChild($case);if(-not $check.Executed){[void]$case.AppendChild($xml.CreateElement('skipped'))}elseif(-not $item.Passed){[void]$case.AppendChild($xml.CreateElement('failure'))}}
  $suite.SetAttribute('tests',[string]$items.Count);$suite.SetAttribute('failures',[string]@($suite.SelectNodes('testcase/failure')).Count);$suite.SetAttribute('skipped',[string]@($suite.SelectNodes('testcase/skipped')).Count)
 }
 $xml.Save((Join-Path $OutputDirectory 'junit.xml'))
 foreach($badge in @('unit','integration','system','coverage')){
  $label=$badge+' '+$RefType.ToLowerInvariant();$color='#9f9f9f';$status='not measured'
  if($badge -in @('unit','integration')){$rows=@($safe|Where-Object {$_.Layer -eq $badge -and $_.Executed});$status=if(-not $rows.Count){'not run'}elseif(@($rows|Where-Object {-not $_.Passed}).Count){'failed'}else{'passed'};$color=if($status -eq 'passed'){'#4c1'}elseif($status -eq 'failed'){'#e05d44'}else{'#9f9f9f'}}
  if($badge -eq 'system'){$status='not run'}
  $title=[Security.SecurityElement]::Escape($label+': '+$status)
  # Match base/script/release/coverage_badge.sh flat-square geometry without external fonts/services.
  $labelWidth=$label.Length*7+12;$valueWidth=$status.Length*7+12;$width=$labelWidth+$valueWidth
  $labelX=[Math]::Floor($labelWidth/2);$valueX=$labelWidth+[Math]::Floor($valueWidth/2)
  $svg='<svg xmlns="http://www.w3.org/2000/svg" width="'+$width+'" height="20" role="img" aria-label="'+$title+'"><title>'+$title+'</title><rect width="'+$labelWidth+'" height="20" fill="#555"/><rect x="'+$labelWidth+'" width="'+$valueWidth+'" height="20" fill="'+$color+'"/><g fill="#fff" font-family="DejaVu Sans,Verdana,Geneva,sans-serif" font-size="11" text-anchor="middle"><text x="'+$labelX+'" y="14">'+$label+'</text><text x="'+$valueX+'" y="14">'+$status+'</text></g></svg>'
  [IO.File]::WriteAllText((Join-Path $OutputDirectory ($badge+'.svg')),$svg,$encoding)
 }
 return [pscustomobject]$report
}
