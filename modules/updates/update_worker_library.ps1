#Requires -Version 5.1
function Invoke-SetupWindowsUpdateWorker {
 param([Parameter(Mandatory=$true)][string]$StateRoot)
 $ErrorActionPreference='Stop'
 function Set-UpdateStage {
  param([string]$Stage,[string]$Detail)
  Write-SetupUpdateProgress -Path (Join-Path $StateRoot 'Update-Progress.json') -Stage $Stage -Detail $Detail
 }
$log=Join-Path $StateRoot ('WindowsUpdate-'+(Get-Date -Format yyyyMMdd-HHmmss)+'.log')
Start-Transcript -Path $log|Out-Null
try{
 Set-UpdateStage '掃描更新' '正在向 Windows Update 查詢適用更新'
 Write-Host '正在掃描 Windows Update 建議的軟體更新，可能需要數分鐘…' -ForegroundColor Cyan
 $session=New-Object -ComObject Microsoft.Update.Session
 $session.ClientApplicationID='NUC Windows Setup'
 $searcher=$session.CreateUpdateSearcher()
 $search=$searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software' and IsAssigned=1")
 $collection=New-Object -ComObject Microsoft.Update.UpdateColl
 $titles=@()
 foreach($update in $search.Updates){
  Write-Host ('找到更新：'+$update.Title)
  if($update.InstallationBehavior.CanRequestUserInput){Write-Warning ('略過需要互動的更新：'+$update.Title);continue}
  if(-not $update.EulaAccepted){$update.AcceptEula()}
  [void]$collection.Add($update);$titles+=$update.Title
 }
 $result=[ordered]@{Found=$search.Updates.Count;Selected=$collection.Count;Titles=$titles;Updates=@();RebootRequired=$false;CompletedAt=$null}
 if($collection.Count){
  Set-UpdateStage '下載更新' ('共 '+$collection.Count+' 項；準備下載，進度將由Windows Update回報')
  Write-Host '正在下載更新…'
  $downloader=$session.CreateUpdateDownloader();$downloader.Updates=$collection
  $downloadResult=Invoke-SetupUpdateOperation -Operation Download -Client $downloader -Titles $titles -ProgressPath (Join-Path $StateRoot 'Update-Progress.json')
  $installSet=New-Object -ComObject Microsoft.Update.UpdateColl
  foreach($update in $collection){if($update.IsDownloaded){[void]$installSet.Add($update)}else{Write-Warning ('尚未下載完成：'+$update.Title)}}
  if($installSet.Count){
   Set-UpdateStage '安裝更新' ('共 '+$installSet.Count+' 項；正在安裝，請勿關機')
   Write-Host '正在安裝更新，請勿關機…'
   $installer=$session.CreateUpdateInstaller();$installer.Updates=$installSet
   $installation=Invoke-SetupUpdateOperation -Operation Install -Client $installer -Titles @($installSet|ForEach-Object Title) -ProgressPath (Join-Path $StateRoot 'Update-Progress.json')
   $result.RebootRequired=$installation.RebootRequired
   for($i=0;$i -lt $installSet.Count;$i++){
    $r=$installation.GetUpdateResult($i)
    $result.Updates+=[pscustomobject]@{Title=$installSet.Item($i).Title;ResultCode=[int]$r.ResultCode;HResult=$r.HResult}
    Write-Host ($installSet.Item($i).Title+'：結果代碼 '+$r.ResultCode)
   }
  }
 }
 $result.RebootRequired=$result.RebootRequired -or (New-Object -ComObject Microsoft.Update.SystemInfo).RebootRequired
 $result.CompletedAt=(Get-Date).ToString('o')
 $result|ConvertTo-Json -Depth 6|Set-Content (Join-Path $StateRoot 'WindowsUpdate-Result.json') -Encoding utf8
 Write-Host ('需要重新開機：'+$result.RebootRequired)
 if(@($result.Updates|Where-Object ResultCode -ne 2).Count -or $result.Updates.Count -ne $collection.Count){throw '部分更新未成功，請查看 WindowsUpdate-Result.json，重新開機後可再次執行。'}
 Set-UpdateStage '本輪完成' ('需要重新開機：'+$result.RebootRequired)
 Write-Host '本輪 Windows Update 已完成；本工具不會自動重新開機。' -ForegroundColor Green
}catch{Set-UpdateStage '更新未完成' $_.Exception.Message;throw}finally{Stop-Transcript|Out-Null}
}