#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$Worker)
$ErrorActionPreference='Stop'
function Set-UpdateStage {
 param([string]$Stage,[string]$Detail)
 @{Stage=$Stage;Detail=$Detail;UpdatedAt=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $PSScriptRoot 'Update-Progress.json') -Encoding UTF8
}
if(-not $Worker){
 $state=Join-Path $env:ProgramData 'NUC8-Setup\WindowsUpdate'
 New-Item -ItemType Directory $state -Force|Out-Null
 $workerPath=Join-Path $state 'Update-Worker.ps1'
 Copy-Item -LiteralPath $PSCommandPath -Destination $workerPath -Force
 $resultPath=Join-Path $state 'WindowsUpdate-Result.json'
 if(Test-Path $resultPath){Move-Item -LiteralPath $resultPath -Destination (Join-Path $state ('Previous-'+(Get-Date -Format yyyyMMdd-HHmmss)+'.json')) -Force}
 $taskName='NUC8-Setup-WindowsUpdate'
 $existing=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
 if($existing -and $existing.State -eq 'Running'){throw 'Windows Update 工作已在執行，請稍後再試。'}
 $action=New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument ('-NoProfile -ExecutionPolicy Bypass -File "'+$workerPath+'" -Worker')
 $principal=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
 $settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 2) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
 Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Force|Out-Null
 @{Stage='正在啟動';Detail='準備掃描更新';UpdatedAt=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $state 'Update-Progress.json') -Encoding UTF8
 Start-ScheduledTask -TaskName $taskName
 Write-Host '已啟動本機 Windows Update 工作，正在等候掃描、下載與安裝…' -ForegroundColor Cyan
 $started=Get-Date
 Start-Sleep -Seconds 3
 do{
  $task=Get-ScheduledTask -TaskName $taskName
  $info=Get-ScheduledTaskInfo -TaskName $taskName
  if($task.State -ne 'Running' -and $info.LastRunTime -ge $started.AddSeconds(-3)){break}
  if((Get-Date) -gt $started.AddHours(2)){throw ('更新尚未完成，可查看：'+$state)}
  $phase='正在啟動';$detail=''
  try{if(Test-Path (Join-Path $state 'Update-Progress.json')){$progress=Get-Content (Join-Path $state 'Update-Progress.json') -Raw|ConvertFrom-Json;$phase=$progress.Stage;$detail=$progress.Detail}}catch{}
  $elapsed=[math]::Round(((Get-Date)-$started).TotalMinutes,1)
  Write-Host ('Windows Update：'+$phase+'；已經過 '+$elapsed+' 分鐘；'+$detail)
  Write-Progress -Id 4 -Activity 'Windows Update' -Status ($phase+'；已經過 '+$elapsed+' 分鐘') -CurrentOperation $detail
  Start-Sleep -Seconds 15
 }while($true)
 Write-Progress -Id 4 -Activity 'Windows Update' -Completed
 if(Test-Path $resultPath){Copy-Item -LiteralPath $resultPath -Destination (Join-Path $PSScriptRoot 'WindowsUpdate-Result.json') -Force;Get-Content $resultPath -Raw|Write-Host}
 Get-ChildItem $state -Filter 'WindowsUpdate-*.log'|ForEach-Object {Copy-Item -LiteralPath $_.FullName -Destination $PSScriptRoot -Force}
 $exitCode=$info.LastTaskResult
 Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
 if($exitCode -ne 0 -or -not(Test-Path $resultPath)){throw ('Windows Update 未完全成功，結束代碼：'+$exitCode+'；請查看紀錄：'+$state)}
 Write-Host 'Windows Update 本輪處理完成，未自動重新開機。' -ForegroundColor Green
 return
}
$log=Join-Path $PSScriptRoot ('WindowsUpdate-'+(Get-Date -Format yyyyMMdd-HHmmss)+'.log')
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
  Set-UpdateStage '下載更新' ('共 '+$collection.Count+' 項；Windows 未提供即時百分比，請勿關閉視窗')
  Write-Host '正在下載更新…'
  $downloader=$session.CreateUpdateDownloader();$downloader.Updates=$collection
  $downloadResult=$downloader.Download()
  $installSet=New-Object -ComObject Microsoft.Update.UpdateColl
  foreach($update in $collection){if($update.IsDownloaded){[void]$installSet.Add($update)}else{Write-Warning ('尚未下載完成：'+$update.Title)}}
  if($installSet.Count){
   Set-UpdateStage '安裝更新' ('共 '+$installSet.Count+' 項；正在安裝，請勿關機')
   Write-Host '正在安裝更新，請勿關機…'
   $installer=$session.CreateUpdateInstaller();$installer.Updates=$installSet
   $installation=$installer.Install()
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
 $result|ConvertTo-Json -Depth 6|Set-Content (Join-Path $PSScriptRoot 'WindowsUpdate-Result.json') -Encoding utf8
 Write-Host ('需要重新開機：'+$result.RebootRequired)
 if(@($result.Updates|Where-Object ResultCode -ne 2).Count -or $result.Updates.Count -ne $collection.Count){throw '部分更新未成功，請查看 WindowsUpdate-Result.json，重新開機後可再次執行。'}
 Set-UpdateStage '本輪完成' ('需要重新開機：'+$result.RebootRequired)
 Write-Host '本輪 Windows Update 已完成；本工具不會自動重新開機。' -ForegroundColor Green
}catch{Set-UpdateStage '更新未完成' $_.Exception.Message;throw}finally{Stop-Transcript|Out-Null}