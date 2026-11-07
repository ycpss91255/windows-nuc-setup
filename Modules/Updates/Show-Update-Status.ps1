#Requires -Version 5.1
$p=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
 Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -File "'+$PSCommandPath+'"');exit
}
$root=Join-Path $env:ProgramData 'NUC8-Setup\WindowsUpdate'
Write-Host 'Windows Update 獨立進度視窗；關閉此視窗不會停止更新。'
while($true){
 Clear-Host
 Write-Host '=== Windows Update 本機工作狀態 ===' -ForegroundColor Cyan
 Write-Host ('更新時間：'+(Get-Date).ToString('yyyy/MM/dd HH:mm:ss'))
 $task=Get-ScheduledTask -TaskName NUC8-Setup-WindowsUpdate -ErrorAction SilentlyContinue
 if($task){$info=Get-ScheduledTaskInfo -TaskName NUC8-Setup-WindowsUpdate;Write-Host ('排程狀態：'+$task.State+'；已經過 '+[math]::Round(((Get-Date)-$info.LastRunTime).TotalMinutes,1)+' 分鐘')}
 $progressPath=Join-Path $root 'Update-Progress.json'
 try{if(Test-Path $progressPath){$progress=Get-Content $progressPath -Raw|ConvertFrom-Json;Write-Host ('目前階段：'+$progress.Stage);Write-Host $progress.Detail}}catch{}
 $latest=Get-ChildItem $root -Filter 'WindowsUpdate-*.log' -ErrorAction SilentlyContinue|Sort-Object LastWriteTime -Descending|Select-Object -First 1
 if($latest){Write-Host '最近的工作訊息：';$lines=Get-Content $latest.FullName -ErrorAction SilentlyContinue;$lines|Where-Object {$_ -match '^(正在|找到更新|需要重新|本輪|KB|202[0-9]-)'}|Select-Object -Last 7|ForEach-Object {Write-Host $_}}
 $resultPath=Join-Path $root 'WindowsUpdate-Result.json'
 if(Test-Path $resultPath){
  try{$r=Get-Content $resultPath -Raw|ConvertFrom-Json;Write-Host ('本輪完成時間：'+$r.CompletedAt);$r.Updates|Select-Object Title,ResultCode,HResult|Format-Table -Wrap|Out-Host;Write-Host ('需要重新開機：'+$r.RebootRequired)}catch{}
 }
 Write-Host ('完整紀錄：'+$root)
 if(-not $task -or $task.State -ne 'Running'){Write-Host '工作目前未在執行；請查看以上結果與紀錄。';break}
 Write-Host '每 10 秒更新。可關閉此視窗，背景更新會繼續。'
 Start-Sleep -Seconds 10
}
Read-Host '按 Enter 關閉'