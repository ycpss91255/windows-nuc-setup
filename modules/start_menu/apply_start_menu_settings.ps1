#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$Worker,[switch]$VerifyOnly,[switch]$ApplyPolicy,[switch]$NonInteractive)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'start_pins_policy_library.ps1')
$assetRoot=Join-Path $PSScriptRoot $(if($Worker){'StartMenuAssets'}else{'assets'})
$resultFileName=if($VerifyOnly){'StartMenu-Verification.json'}else{'StartMenu-Result.json'}
$root=Join-Path $env:ProgramData 'NUC8-Setup'
New-Item -ItemType Directory $root -Force|Out-Null
if(-not $Worker -and [Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0){
 $workerPath=Join-Path $root 'StartMenu-Worker.ps1'
 Copy-Item $PSCommandPath $workerPath -Force
 foreach($helper in @('start_pins_policy_library.ps1','start_pins_asset_library.ps1')){Copy-Item (Join-Path $PSScriptRoot $helper) (Join-Path $root $helper) -Force}
 $workerAssets=Join-Path $root 'StartMenuAssets';New-Item -ItemType Directory $workerAssets -Force|Out-Null
 foreach($file in @('empty_start.xml','empty_start.ppkg','provenance.json')){Copy-Item (Join-Path $assetRoot $file) (Join-Path $workerAssets $file) -Force}
 $resultPath=Join-Path $root $resultFileName
 if(Test-Path $resultPath){Remove-Item $resultPath -Force}
 $name='NUC8-Apply-StartMenu'
 $workerArgs='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$workerPath+'" -Worker'
 if($VerifyOnly){$workerArgs+=' -VerifyOnly'}
 if($ApplyPolicy){$workerArgs+=' -ApplyPolicy'}
 if($NonInteractive -or $ApplyPolicy){$workerArgs+=' -NonInteractive'}
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
 if(-not $result.Success -and $result.Status -notin @('LegacyPendingApply','PendingSignIn')){throw $result.Error}
 return $result
}
try{
 $key='HKCU:\Software\Policies\Microsoft\Windows\Explorer'
 if(-not $VerifyOnly){
  if(-not(Test-Path $key)){New-Item $key -Force|Out-Null}
  New-ItemProperty $key -Name HideRecommendedSection -PropertyType DWord -Value 1 -Force|Out-Null
  $advanced='HKCU:\Software\Microsoft\Windows\CurrentVersion\explorer\Advanced'
  foreach($name in @('Start_TrackDocs','Start_TrackProgs','Start_IrisRecommendations')){New-ItemProperty $advanced -Name $name -PropertyType DWord -Value 0 -Force|Out-Null}
  $listKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
  if(-not(Test-Path $listKey)){New-Item $listKey -Force|Out-Null}
  New-ItemProperty $listKey -Name NoStartMenuMorePrograms -PropertyType DWord -Value 1 -Force|Out-Null
 }
 $result=Invoke-StartPinsConfiguration -AssetRoot $assetRoot -OutputRoot $root -VerifyOnly:$VerifyOnly -ApplyPolicy:$ApplyPolicy -NonInteractive:$NonInteractive
 if($result.Success -and (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer').NoStartMenuMorePrograms -ne 1){$result.Success=$false;$result.Status='Failed';$result.Error='開始選單應用程式清單設定未生效。'}
 $result|ConvertTo-Json|Set-Content (Join-Path $root $resultFileName) -Encoding UTF8
 if($result.Status -eq 'Failed'){throw $result.Error}
 if($result.Success){Write-Host '已由原生匯出確認開始選單釘選清空。' -ForegroundColor Green}
 elseif($result.Status -eq 'LegacyPendingApply'){Write-Warning '開始選單政策待處理：其他設定全部完成後，才可明確同意套用舊版政策。'}
 else{Write-Warning '開始選單政策已準備，但原生匯出尚未確認釘選清空；請完成其餘工作後手動重新登入，再執行 windows.cmd -AfterRestart。'}
 return [pscustomobject]$result
}catch{
 @{Success=$false;Error=$_.Exception.Message}|ConvertTo-Json|Set-Content (Join-Path $root $resultFileName) -Encoding UTF8
 throw
}


