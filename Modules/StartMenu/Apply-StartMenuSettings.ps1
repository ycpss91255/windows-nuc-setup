#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$Worker,[switch]$VerifyOnly)
$ErrorActionPreference='Stop'
$resultFileName=if($VerifyOnly){'StartMenu-Verification.json'}else{'StartMenu-Result.json'}
$root=Join-Path $env:ProgramData 'NUC8-Setup'
New-Item -ItemType Directory $root -Force|Out-Null
if(-not $Worker -and [Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0){
 $workerPath=Join-Path $root 'StartMenu-Worker.ps1'
 Copy-Item $PSCommandPath $workerPath -Force
 $resultPath=Join-Path $root $resultFileName
 if(Test-Path $resultPath){Remove-Item $resultPath -Force}
 $name='NUC8-Apply-StartMenu'
 $workerArgs='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$workerPath+'" -Worker'
 if($VerifyOnly){$workerArgs+=' -VerifyOnly'}
 $action=New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument $workerArgs
 $principal=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Highest
 Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -Force|Out-Null
 Start-ScheduledTask -TaskName $name
 $deadline=(Get-Date).AddSeconds(60)
 do{Start-Sleep -Seconds 2;$task=Get-ScheduledTask -TaskName $name;if(Test-Path $resultPath){break}}while((Get-Date) -lt $deadline)
 if($task.State -ne 'Running'){Unregister-ScheduledTask -TaskName $name -Confirm:$false}
 if(-not(Test-Path $resultPath)){throw '60 秒內未取得開始選單工作結果；工作可能仍在執行，請等待工作結束後再重新驗證。'}
 $result=Get-Content $resultPath -Raw|ConvertFrom-Json
 if($resultPath -ne (Join-Path $PSScriptRoot $resultFileName)){Copy-Item $resultPath (Join-Path $PSScriptRoot $resultFileName) -Force}
 $result|Format-List|Out-Host
 if(-not $result.Success){throw $result.Error}
 return
}
try{
 $key='HKCU:\Software\Policies\Microsoft\Windows\Explorer'
 $layout=Join-Path $root 'EmptyStartLayout.json'
 if(-not $VerifyOnly){
  '{"pinnedList":[],"applyOnce":true}'|Set-Content $layout -Encoding UTF8
  if(-not(Test-Path $key)){New-Item $key -Force|Out-Null}
  New-ItemProperty $key -Name ConfigureStartPins -PropertyType DWord -Value 1 -Force|Out-Null
  New-ItemProperty $key -Name ConfigureStartPinsJSON -PropertyType String -Value $layout -Force|Out-Null
  New-ItemProperty $key -Name HideRecommendedSection -PropertyType DWord -Value 1 -Force|Out-Null
  $advanced='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
  foreach($name in @('Start_TrackDocs','Start_TrackProgs','Start_IrisRecommendations')){New-ItemProperty $advanced -Name $name -PropertyType DWord -Value 0 -Force|Out-Null}
  $listKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
  if(-not(Test-Path $listKey)){New-Item $listKey -Force|Out-Null}
  New-ItemProperty $listKey -Name NoStartMenuMorePrograms -PropertyType DWord -Value 1 -Force|Out-Null
  $session=[Diagnostics.Process]::GetCurrentProcess().SessionId
  Get-Process StartMenuExperienceHost -ErrorAction SilentlyContinue|Where-Object SessionId -eq $session|Stop-Process -Force
  Start-Sleep -Seconds 3
 }
 $export=Join-Path $root ('StartMenu-Actual-'+[guid]::NewGuid().ToString('N')+'.json')
 Export-StartLayout -Path $export -ErrorAction Stop
 $actual=Get-Content $export -Raw|ConvertFrom-Json
 $result=[ordered]@{Success=(@($actual.pinnedList).Count -eq 0 -and (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer').NoStartMenuMorePrograms -eq 1);PinCount=@($actual.pinnedList).Count;ExportPath=$export;CheckedAt=(Get-Date).ToString('o')}
 $result|ConvertTo-Json|Set-Content (Join-Path $root $resultFileName) -Encoding UTF8
 if(-not $result.Success){throw ('開始選單仍有 '+$result.PinCount+' 個釘選。')}
 Write-Host '已確認開始選單釘選清空。' -ForegroundColor Green
}catch{
 @{Success=$false;Error=$_.Exception.Message}|ConvertTo-Json|Set-Content (Join-Path $root $resultFileName) -Encoding UTF8
 throw
}


