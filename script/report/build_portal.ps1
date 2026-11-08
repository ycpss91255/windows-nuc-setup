#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$CatalogPath,[Parameter(Mandatory=$true)][string]$OutputDirectory,[string]$MainSnapshotPath,[switch]$RequireGoCoverage)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../test/test_report.ps1')
. (Join-Path $PSScriptRoot 'portal.ps1')
$output=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
if(Test-Path -LiteralPath $output){throw 'Portal 輸出必須是新目錄，避免混入過期版本頁。'}
New-Item -ItemType Directory $output|Out-Null
$utf8=[Text.UTF8Encoding]::new($false)
$catalog=Get-Content -LiteralPath $CatalogPath -Raw -Encoding UTF8|ConvertFrom-Json
$snapshots=@{};$versions=New-Object Collections.Generic.List[object]
foreach($entry in $catalog){
 if($entry.Version -cnotmatch '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-rc[1-9][0-9]*)?$'){continue}
 if(@($versions|Where-Object Version -ceq $entry.Version).Count){throw '重複版本，拒絕覆寫。'}
 $dir=Join-Path $output ('versions/'+$entry.Version)
 $state='Unknown';$reason='此舊版本未提供可驗證品質快照；不以目前 CI 回填。';$evidence=$null
 if($entry.SnapshotPath -and $entry.ManifestPath){
  try{$evidence=Test-PortalReleaseEvidence $entry}catch{$reason='品質證據未通過驗證：'+(Protect-ReportText $_.Exception.Message);$state='Invalid'}
 }
 if($evidence){
  New-Item -ItemType Directory $dir -Force|Out-Null
  foreach($file in $evidence.Manifest.Files){
   $source=if($file.Name -eq 'summary.json'){$entry.SnapshotPath}else{Join-Path $entry.AssetDirectory $file.Name}
   Copy-Item -LiteralPath $source -Destination (Join-Path $dir $file.Name)
  }
  $snapshots[$entry.Version]=$evidence.Snapshot;$state='Verified';$reason='原始量測與不可變 Release digest 已核對。'
 }else{
  New-Item -ItemType Directory $dir -Force|Out-Null
  $safeVersion=[Net.WebUtility]::HtmlEncode($entry.Version);$safeReason=[Net.WebUtility]::HtmlEncode($reason)
  [IO.File]::WriteAllText((Join-Path $dir 'index.html'),('<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><title>'+ $safeVersion +' · 測試紀錄</title><h1>'+ $safeVersion +'</h1><p>'+ $safeReason +'</p><p>這個版本未保存可用的測試紀錄，無法判斷當時的測試結果。</p><a href="../../index.html">版本索引</a></html>'),$utf8)
 }
 $versions.Add([pscustomobject]@{Version=$entry.Version;Commit=$entry.Commit;Status=$state;Reason=$reason;Path=('versions/'+$entry.Version+'/index.html');ReleaseUrl=$entry.ReleaseUrl;MeasuredAt=$(if($evidence){$evidence.Snapshot.MeasuredAt}else{'Unknown'});Digest=$entry.SnapshotDigest})
}
$mainStatus='Unknown'
if($RequireGoCoverage -and (-not $MainSnapshotPath -or -not(Test-Path -LiteralPath $MainSnapshotPath -PathType Leaf))){throw 'main 發布必須提供 Go 覆蓋率報告。'}
if($MainSnapshotPath -and (Test-Path -LiteralPath $MainSnapshotPath)){
 $main=Get-Content -LiteralPath $MainSnapshotPath -Raw -Encoding UTF8|ConvertFrom-Json
 Assert-TestReportSnapshot -Report $main
 if($main.RefType -cne 'Branch' -or $main.RefName -cne 'main' -or $main.SourceState -cne 'Clean' -or $main.RequestedLayer -cne 'All'){throw 'main 品質來源標記不符。'}
 $hasGo=$null -ne $main.PSObject.Properties['GoCoverage']
 if($RequireGoCoverage -and -not $hasGo){throw 'main 發布缺少 Go 覆蓋率。'}
 if($hasGo){Assert-GoCoverageProfile -Coverage $main.GoCoverage -Directory (Split-Path -Parent $MainSnapshotPath)}
 Write-SnapshotView $main (Join-Path $output 'main');$mainStatus='Available'
 if($hasGo){Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $MainSnapshotPath) 'go_coverage.out') -Destination (Join-Path $output 'main/go_coverage.out')}
}
$pairs=Join-Path $output 'comparisons';New-Item -ItemType Directory $pairs|Out-Null
foreach($a in $versions){foreach($b in $versions){$comparison=Compare-TestSnapshots $snapshots[$a.Version] $snapshots[$b.Version];[IO.File]::WriteAllText((Join-Path $pairs ($a.Version+'--'+$b.Version+'.json')),($comparison|ConvertTo-Json -Depth 10),$utf8)}}
[IO.File]::WriteAllText((Join-Path $output 'versions.json'),(ConvertTo-Json -InputObject @($versions.ToArray()) -Depth 6),$utf8)
$links=(@($versions|ForEach-Object {
 $label=if($_.Status -eq 'Verified'){'已保存測試紀錄'}elseif($_.Status -eq 'Invalid'){'測試紀錄無法驗證'}else{'未保存測試紀錄'}
 '<li><a href="'+$_.Path+'">'+[Net.WebUtility]::HtmlEncode($_.Version)+'</a> · '+$label+'</li>'
}) -join '')
if(-not $links){$links='<li>目前沒有已發布版本。</li>'}
$mainLink='<h2>尚無本次報告</h2><p>目前沒有可核對的最新程式檢查結果，請稍後查看或開啟執行紀錄。</p>'
if($mainStatus -eq 'Available'){
 $headline=if($main.Success){'目前程式檢查通過'}else{'目前程式檢查未通過'}
 $stamp=([DateTimeOffset]::Parse($main.MeasuredAt)).UtcDateTime.ToString('yyyy-MM-dd HH:mm:ss')+' UTC'
 $shortCommit=if($main.Commit.Length -ge 7){$main.Commit.Substring(0,7)}else{$main.Commit}
 $mainLink='<h2>'+$headline+'</h2><p>檢查對象：開發主線 main · 提交 <code>'+[Net.WebUtility]::HtmlEncode($shortCommit)+'</code><br>檢查時間：'+[Net.WebUtility]::HtmlEncode($stamp)+'</p><p>已執行程式邏輯檢查（單元測試），以及隔離環境中的模組配合檢查（整合測試）。</p><p><a class="button" href="main/index.html">查看本次檢查明細</a></p>'
}
$coverageNotice='程式碼覆蓋率尚未量測。'
if($mainStatus -eq 'Available' -and $hasGo){
 $coverageNotice='Go 程式敘述覆蓋率：'+(Get-GoCoveragePercentText $main.GoCoverage)+'（'+$main.GoCoverage.Covered+'/'+$main.GoCoverage.TotalStatements+' statements）。範圍為全部自有 Go 工具（含 CLI），不含 PowerShell 或第三方程式；PowerShell 覆蓋率尚未量測。'
}
$html=@'
<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Windows 設定工具｜測試結果</title><style>body{font:16px/1.65 system-ui;max-width:960px;margin:36px auto;padding:0 20px;color:#17202a;background:#f7f9fb}h1{font-size:28px}h2{font-size:22px;margin-top:0}.card,details{background:white;border:1px solid #dce3ea;border-radius:10px;padding:24px;margin:20px 0}.notice{border-left:4px solid #b27b14;padding:12px 18px;background:#fff8e8}a{color:#1558ad}.button{display:inline-block;padding:8px 14px;border:1px solid #1558ad;border-radius:6px;text-decoration:none}summary{cursor:pointer;font-weight:600}select,button{padding:8px;font:inherit}li{margin:8px 0}code{font-size:14px}.muted{color:#526170}</style><body><h1>Windows 設定工具｜測試結果</h1><p>這裡告訴你程式檢查是否通過，以及哪些操作還沒有實際驗證。</p><section class="card">@@MAIN@@</section><section class="notice"><strong>完整安裝尚未實測</strong><p>目前還沒有完成「全新 Windows → 初始化帳號 → 套用設定 → 重新開機」的整套實機測試。程式檢查通過，不代表每臺電腦都已安裝成功；驅動與桌面設定仍需在目標電腦確認。@@COVERAGE@@</p></section><section class="card"><h2>準備使用</h2><p>請先依操作說明準備工具包，再從 USB 執行。GitHub 的來源下載不包含 Autologon 或獨立驅動包。</p><a class="button" href="https://github.com/ycpss91255/windows_setup/blob/main/readme.md">查看 USB 安裝與使用步驟</a> <a href="https://github.com/ycpss91255/windows_setup/actions/workflows/windows_tests.yml">查看檢查執行紀錄</a></section><details><summary>舊版本與進階比較</summary><p>較早版本未保存測試紀錄時，這裡不會用現在的結果代替。</p><ul>@@VERSIONS@@</ul><h2>比較兩個版本</h2><label>基準 <select id="baseline"></select></label> <label>比較 <select id="candidate"></select></label> <button id="compare">比較</button><p class="muted">只有兩個版本都有完整且相容的測試紀錄，才能比較新增、移除或失敗的檢查。這不是完整 Windows 安裝結果的比較。</p><div id="result" aria-live="polite"></div></details><script src="compare.js"></script></body></html>
'@
[IO.File]::WriteAllText((Join-Path $output 'index.html'),$html.Replace('@@MAIN@@',$mainLink).Replace('@@VERSIONS@@',$links).Replace('@@COVERAGE@@',[Net.WebUtility]::HtmlEncode($coverageNotice)),$utf8)
$js=@'
const base=document.getElementById('baseline'),candidate=document.getElementById('candidate'),result=document.getElementById('result');
fetch('versions.json').then(r=>{if(!r.ok)throw Error('版本索引 unavailable');return r.json()}).then(rows=>{for(const row of rows){for(const select of [base,candidate]){const option=document.createElement('option');option.value=row.Version;option.textContent=row.Version+' · '+(row.Status==='Verified'?'已保存紀錄':row.Status==='Invalid'?'紀錄無法驗證':'未保存紀錄');select.append(option)}}}).catch(e=>result.textContent='暫時無法讀取測試紀錄，請稍後再試。');
document.getElementById('compare').onclick=async()=>{result.textContent='讀取比較…';try{const response=await fetch('comparisons/'+encodeURIComponent(base.value)+'--'+encodeURIComponent(candidate.value)+'.json');if(!response.ok)throw Error('缺少比較證據');const data=await response.json();result.textContent='';const conclusion=document.createElement('p');conclusion.textContent=data.Status==='Compared'?'基準 '+data.BaselineVersion+' → '+data.CandidateVersion+'；程式碼覆蓋率尚未量測。':'這兩個版本缺少可比較的測試紀錄。'+(data.Reason||'');result.append(conclusion);if(data.Status!=='Compared')return;for(const [key,label] of [['Added','新增'],['Removed','移除'],['NewFailures','新失敗'],['Fixed','已修復'],['NotRun','未執行']]){const heading=document.createElement('h3');heading.textContent=label+'：'+(data[key]||[]).length;result.append(heading);const list=document.createElement('ul');for(const name of data[key]||[]){const item=document.createElement('li');item.textContent=name;list.append(item)}result.append(list)}}catch(e){result.textContent='暫時無法讀取測試紀錄，請稍後再試。'}};
'@
[IO.File]::WriteAllText((Join-Path $output 'compare.js'),$js,$utf8)
[pscustomobject]@{OutputDirectory=$output;Versions=$versions.Count;MainStatus=$mainStatus}
