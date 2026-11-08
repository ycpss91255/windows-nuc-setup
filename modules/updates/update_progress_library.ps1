#Requires -Version 5.1
function New-SetupUpdateCallback {
 if(-not ('WindowsSetup.UpdateCallback' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'native/update_callback.cs')}
 return New-Object WindowsSetup.UpdateCallback
}
function Write-SetupUpdateProgress {
 param([string]$Path,[string]$Stage,[string]$Detail,[Nullable[int]]$PercentComplete,
 [Nullable[int]]$CurrentUpdate,[Nullable[int]]$TotalUpdates,[string]$CurrentTitle,[Nullable[int]]$CurrentPercent)
 $row=[ordered]@{Stage=$Stage;Detail=$Detail;UpdatedAt=(Get-Date).ToString('o');PercentComplete=$PercentComplete;CurrentUpdate=$CurrentUpdate;TotalUpdates=$TotalUpdates;CurrentTitle=$CurrentTitle;CurrentPercent=$CurrentPercent}
 $temporary=$Path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 [IO.File]::WriteAllText($temporary,($row|ConvertTo-Json),(New-Object Text.UTF8Encoding($true)))
 try{if(Test-Path -LiteralPath $Path){[IO.File]::Replace($temporary,$Path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temporary,$Path)}}finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
 Write-Host ($Stage+'：'+$Detail)
}
function Invoke-SetupUpdateOperation {
 param([Parameter(Mandatory=$true)][ValidateSet('Download','Install')][string]$Operation,
 [Parameter(Mandatory=$true)]$Client,[Parameter(Mandatory=$true)][string[]]$Titles,
 [Parameter(Mandatory=$true)][string]$ProgressPath,[ValidateRange(0,6600)][int]$TimeoutSeconds=3000,
 [ValidateRange(0,60)][int]$PollSeconds=5)
 $ErrorActionPreference='Stop'
 if(-not $Titles.Count){throw '非同步更新清單不可空白。'}
 if($Operation -eq 'Install' -and $Client.IsBusy){throw 'Windows Update 安裝器正在忙碌，未啟動第二份工作。'}
 $progressCallback=New-SetupUpdateCallback;$completedCallback=New-SetupUpdateCallback
 $job=$null;$ended=$false;$clock=[Diagnostics.Stopwatch]::StartNew()
 $begin='Begin'+$Operation;$end='End'+$Operation;$stage=if($Operation -eq 'Download'){'下載更新'}else{'安裝更新'}
 try{
  $job=$Client.$begin($progressCallback,$completedCallback,$null)
  if($null -eq $job){throw 'WUA未回傳工作物件。'}
  while($true){
   $progress=$job.GetProgress();$percent=[int]$progress.PercentComplete;$index=[int]$progress.CurrentUpdateIndex;$itemPercent=[int]$progress.CurrentUpdatePercentComplete
   if($percent -lt 0 -or $percent -gt 100 -or $itemPercent -lt 0 -or $itemPercent -gt 100){throw 'WUA回傳無效百分比。'}
   $current=$null;$title='';if($index -ge 0 -and $index -lt $Titles.Count){$current=$index+1;$title=$Titles[$index]}
   $detail=('{0}%；目前 {1}/{2}；{3}；單項 {4}%' -f $percent,$current,$Titles.Count,$title,$itemPercent)
   Write-SetupUpdateProgress -Path $ProgressPath -Stage $stage -Detail $detail -PercentComplete $percent -CurrentUpdate $current -TotalUpdates $Titles.Count -CurrentTitle $title -CurrentPercent $itemPercent
   if($job.IsCompleted){break}
   if($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds){throw ('Windows Update '+$stage+'逾時，已要求中止；不會自動啟動另一份更新。')}
   Start-Sleep -Seconds $PollSeconds
  }
  $ended=$true
  return $Client.$end($job)
 }catch{
  $failure=$_
  # CleanUp can wait for WUA. Persist the failure before entering COM cancellation/cleanup.
  try{Write-SetupUpdateProgress -Path $ProgressPath -Stage '更新未完成' -Detail ($failure.Exception.Message+'；正在等候WUA中止與清理，不代表已停止。')}catch{Write-Warning ('進度紀錄寫入失敗：'+$_.Exception.Message)}
  if($null -ne $job -and -not $ended){
   try{if(-not $job.IsCompleted){$job.RequestAbort()};if($job.IsCompleted){$ended=$true;$null=$Client.$end($job)}}catch{Write-Warning ('更新中止/結束失敗：'+$_.Exception.Message)}
  }
  throw $failure
 }finally{
  $clock.Stop()
  if($null -ne $job){$job.CleanUp()}
  # Callback references are retained until the owning job has been disconnected.
  $progressCallback=$null;$completedCallback=$null
 }
}