#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$CatalogPath,[Parameter(Mandatory=$true)][string]$OutputDirectory,[string]$MainSnapshotPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../test/Test-Report.ps1')
. (Join-Path $PSScriptRoot 'Portal.ps1')
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
  [IO.File]::WriteAllText((Join-Path $dir 'index.html'),('<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><title>'+ $safeVersion +' · Unknown</title><h1>'+ $safeVersion +' · '+$state+'</h1><p>'+ $safeReason +'</p><p>Tests / Coverage：Unknown。沒有品質快照不代表測試通過。</p><a href="../../index.html">版本索引</a></html>'),$utf8)
 }
 $versions.Add([pscustomobject]@{Version=$entry.Version;Commit=$entry.Commit;Status=$state;Reason=$reason;Path=('versions/'+$entry.Version+'/index.html');ReleaseUrl=$entry.ReleaseUrl;MeasuredAt=$(if($evidence){$evidence.Snapshot.MeasuredAt}else{'Unknown'});Digest=$entry.SnapshotDigest})
}
$mainStatus='Unknown'
if($MainSnapshotPath -and (Test-Path -LiteralPath $MainSnapshotPath)){
 $main=Get-Content -LiteralPath $MainSnapshotPath -Raw -Encoding UTF8|ConvertFrom-Json
 Assert-TestReportSnapshot -Report $main
 if($main.RefType -cne 'Branch' -or $main.RefName -cne 'main' -or $main.SourceState -cne 'Clean' -or $main.RequestedLayer -cne 'All'){throw 'main 品質來源標記不符。'}
 Write-SnapshotView $main (Join-Path $output 'main');$mainStatus='Available'
}
$pairs=Join-Path $output 'comparisons';New-Item -ItemType Directory $pairs|Out-Null
foreach($a in $versions){foreach($b in $versions){$comparison=Compare-TestSnapshots $snapshots[$a.Version] $snapshots[$b.Version];[IO.File]::WriteAllText((Join-Path $pairs ($a.Version+'--'+$b.Version+'.json')),($comparison|ConvertTo-Json -Depth 10),$utf8)}}
[IO.File]::WriteAllText((Join-Path $output 'versions.json'),(ConvertTo-Json -InputObject @($versions.ToArray()) -Depth 6),$utf8)
$links=(@($versions|ForEach-Object {'<li><a href="'+$_.Path+'">'+[Net.WebUtility]::HtmlEncode($_.Version)+'</a> · '+$_.Status+' · '+[Net.WebUtility]::HtmlEncode($_.MeasuredAt)+'</li>'}) -join '')
$mainLink=if($mainStatus -eq 'Available'){'<a href="main/index.html">最近 main 品質報表</a>'}else{'main 品質報表：Unknown（目前沒有可驗證的完整快照）'}
$html=@'
<!doctype html><html lang="zh-Hant"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Windows 設定工具 · 版本品質</title><style>body{font:16px system-ui;max-width:1000px;margin:32px auto;padding:16px}section{padding:16px;border:1px solid #aaa;margin:20px 0}pre{white-space:pre-wrap}select,button{padding:8px}li{margin:8px 0}</style><h1>版本品質與測試證據</h1><p>main 是最近部署的分支快照，版本頁固定為該版本量測。System/E2E 尚未執行；Coverage 未量測。這是報表發布，不代表 Windows 安裝部署成功。</p><section>@@MAIN@@</section><h2>所有已發布版本</h2><ul>@@VERSIONS@@</ul><section><h2>比較兩個版本</h2><label>基準 <select id="baseline"></select></label> <label>比較 <select id="candidate"></select></label> <button id="compare">比較</button><p>按套件與斷言名稱識別測試；缺少任一品質證據會顯示 Unknown，Coverage 差異不假造百分比。</p><div id="result" aria-live="polite"></div></section><script src="compare.js"></script></html>
'@
[IO.File]::WriteAllText((Join-Path $output 'index.html'),$html.Replace('@@MAIN@@',$mainLink).Replace('@@VERSIONS@@',$links),$utf8)
$js=@'
const base=document.getElementById('baseline'),candidate=document.getElementById('candidate'),result=document.getElementById('result');
fetch('versions.json').then(r=>{if(!r.ok)throw Error('版本索引 unavailable');return r.json()}).then(rows=>{for(const row of rows){for(const select of [base,candidate]){const option=document.createElement('option');option.value=row.Version;option.textContent=row.Version+' · '+row.Status;select.append(option)}}}).catch(e=>result.textContent='Unknown：'+e.message);
document.getElementById('compare').onclick=async()=>{result.textContent='讀取比較…';try{const response=await fetch('comparisons/'+encodeURIComponent(base.value)+'--'+encodeURIComponent(candidate.value)+'.json');if(!response.ok)throw Error('缺少比較證據');const data=await response.json();result.textContent='';const conclusion=document.createElement('p');conclusion.textContent=data.Status==='Compared'?'基準 '+data.BaselineVersion+' → '+data.CandidateVersion+'；Coverage 差異：'+data.CoverageDelta:'Unknown：'+data.Reason;result.append(conclusion);if(data.Status!=='Compared')return;for(const [key,label] of [['Added','新增'],['Removed','移除'],['NewFailures','新失敗'],['Fixed','已修復'],['NotRun','未執行']]){const heading=document.createElement('h3');heading.textContent=label+'：'+(data[key]||[]).length;result.append(heading);const list=document.createElement('ul');for(const name of data[key]||[]){const item=document.createElement('li');item.textContent=name;list.append(item)}result.append(list)}}catch(e){result.textContent='Unknown：'+e.message}};
'@
[IO.File]::WriteAllText((Join-Path $output 'compare.js'),$js,$utf8)
[pscustomobject]@{OutputDirectory=$output;Versions=$versions.Count;MainStatus=$mainStatus}
