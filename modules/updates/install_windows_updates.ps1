#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$Worker)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'update_stage_library.ps1')
$commonDataRoot=[Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
if(-not $Worker){
 $taskName='NUC8-Setup-WindowsUpdate'
 $existing=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
 if($existing -and $existing.State -eq 'Running'){throw 'Windows Update 工作已在執行，請稍後再試。'}
 $stage=New-SetupUpdateStage -SourceRoot $PSScriptRoot -CommonDataRoot $commonDataRoot -UserSid ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value) -Computer $env:COMPUTERNAME
 try{
 $state=$stage.Path
 $existing=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
 if($existing -and $existing.State -eq 'Running'){throw 'Windows Update 工作已在執行，未註冊或重啟。'}
 $workerPath=Join-Path $state 'Update-Worker.ps1'
 $resultPath=Join-Path $state 'WindowsUpdate-Result.json'
 if(Test-Path $resultPath){Assert-SetupUpdateProtectedPath $resultPath;Move-Item -LiteralPath $resultPath -Destination (Join-Path $state ('Previous-'+(Get-Date -Format yyyyMMdd-HHmmss)+'.json')) -Force}

 $action=New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument ('-NoProfile -ExecutionPolicy Bypass -File "'+$workerPath+'" -Worker')
 $principal=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
 $settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 2) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
 $null=Read-SetupUpdateContext -StageRoot $state
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
  $phase='正在啟動';$detail='';$progress=$null;$percent=-1;$heartbeat='等待首次回報'
  try{if(Test-Path (Join-Path $state 'Update-Progress.json')){$progress=Get-Content (Join-Path $state 'Update-Progress.json') -Raw|ConvertFrom-Json;$phase=$progress.Stage;$detail=$progress.Detail}}catch{}
  if($null -ne $progress){$heartbeat=[string]$progress.UpdatedAt;if($null -ne $progress.PercentComplete){$percent=[int]$progress.PercentComplete}}
  $elapsed=[math]::Round(((Get-Date)-$started).TotalMinutes,1)
  Write-Host ('Windows Update：'+$phase+'；已經過 '+$elapsed+' 分鐘；'+$detail+'；最後回報 '+$heartbeat)
  Write-Progress -Id 4 -Activity 'Windows Update' -Status ($phase+'；已經過 '+$elapsed+' 分鐘；最後回報 '+$heartbeat) -CurrentOperation $detail -PercentComplete $percent
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
 }finally{$stage.Lock.Dispose()}
}
$expectedStage=Join-Path $commonDataRoot 'windows_setup_update'
if([IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\') -ine [IO.Path]::GetFullPath($expectedStage).TrimEnd('\')){throw 'SYSTEM worker只能從本機受保護stage執行。'}
Assert-SetupUpdateAncestors $commonDataRoot
$context=Read-SetupUpdateContext -StageRoot $PSScriptRoot
. (Join-Path $PSScriptRoot 'update_progress_library.ps1')
. (Join-Path $PSScriptRoot 'update_worker_library.ps1')
Invoke-SetupWindowsUpdateWorker -StateRoot $PSScriptRoot -Context $context
