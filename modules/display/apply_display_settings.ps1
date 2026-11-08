#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$Worker,[switch]$VerifyOnly,[ValidatePattern('^[a-fA-F0-9-]{36}$')][string]$VerificationRunId)
$ErrorActionPreference='Stop'
$resultFileName=if($VerifyOnly){'Display-Verification.json'}else{'Display-Result.json'}
$root=Join-Path $env:ProgramData 'NUC8-Setup'
New-Item -ItemType Directory $root -Force|Out-Null
if(-not $Worker -and [Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0){
 $workerPath=Join-Path $root 'Display-Worker.ps1'
 . (Join-Path $PSScriptRoot '../native/managed_source_library.ps1')
 $null=Copy-SetupManagedSource -SourceRoot $PSScriptRoot -DestinationRoot $root -FileName 'display.cs'
 Copy-Item -LiteralPath $PSCommandPath -Destination $workerPath -Force
 $resultPath=Join-Path $root $resultFileName
 if(Test-Path $resultPath){Move-Item -LiteralPath $resultPath -Destination (Join-Path $root ('Display-Previous-'+(Get-Date -Format yyyyMMdd-HHmmss)+'.json')) -Force}
 $name='NUC8-Apply-Display'
 $workerArgs='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$workerPath+'" -Worker'
 if($VerifyOnly){$workerArgs+=' -VerifyOnly'}
 if($VerificationRunId){$workerArgs+=' -VerificationRunId '+$VerificationRunId}
 $action=New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument $workerArgs
 $principal=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Highest
 Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -Force|Out-Null
 Start-ScheduledTask -TaskName $name
 Write-Host '正在目前登入的桌面套用 1920×1080 與 100% 縮放…' -ForegroundColor Cyan
 $deadline=(Get-Date).AddSeconds(60)
 do{Start-Sleep -Seconds 2;$task=Get-ScheduledTask -TaskName $name;if(Test-Path $resultPath){break}}while((Get-Date) -lt $deadline)
 $info=Get-ScheduledTaskInfo -TaskName $name
 if($task.State -ne 'Running'){Unregister-ScheduledTask -TaskName $name -Confirm:$false}
 if(-not(Test-Path $resultPath)){throw ('尚未取得桌面執行結果。請在目標電腦登入桌面後再執行；工作狀態：'+$info.LastTaskResult)}
 $result=Get-Content $resultPath -Raw|ConvertFrom-Json
 if($resultPath -ne (Join-Path $PSScriptRoot $resultFileName)){Copy-Item -LiteralPath $resultPath -Destination (Join-Path $PSScriptRoot $resultFileName) -Force}
 $result|Format-List|Out-Host
 if(-not $result.Success){throw $result.Error}
 return
}
try{
Add-Type -Path (Join-Path $PSScriptRoot 'native/display.cs')
 if($VerifyOnly){
  $actual=[NUC8Display.Display]::Read()
  $result=[ordered]@{VerificationRunId=$VerificationRunId;Computer=$env:COMPUTERNAME;UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Success=($actual[0] -eq 1920 -and $actual[1] -eq 1080 -and $actual[2] -eq 96 -and (Get-ItemProperty 'HKCU:\Control Panel\Desktop' -ErrorAction SilentlyContinue).Win8DpiScaling -ne 1);Width=$actual[0];Height=$actual[1];CurrentMonitorDPI=$actual[2];CurrentScalePercent=[math]::Round($actual[2]*100/96);CustomScalingEnabled=((Get-ItemProperty 'HKCU:\Control Panel\Desktop' -ErrorAction SilentlyContinue).Win8DpiScaling -eq 1);VerifiedAt=(Get-Date).ToString('o');Error='解析度或實際 DPI 尚未符合 1920×1080 / 100%，可能需要重新登入。'}
  if($result.Success){$result.Error=$null}
  $result|ConvertTo-Json|Set-Content (Join-Path $root 'Display-Verification.json') -Encoding UTF8
  if((Join-Path $PSScriptRoot 'Display-Verification.json') -ne (Join-Path $root 'Display-Verification.json')){$result|ConvertTo-Json|Set-Content (Join-Path $PSScriptRoot 'Display-Verification.json') -Encoding UTF8}
  $result|Format-List|Out-Host
  return
 }
 $values=[NUC8Display.Display]::Apply()
 $desktop='HKCU:\Control Panel\Desktop'
 # 關閉先前的全域自訂縮放，改用螢幕的標準縮放預設值。
 New-ItemProperty $desktop -Name Win8DpiScaling -Value 0 -PropertyType DWord -Force|Out-Null
 Remove-ItemProperty $desktop -Name LogPixels -ErrorAction SilentlyContinue
 $nativeScales=@([NUC8Display.Display]::NativeScales($true))
 if(@($nativeScales|Where-Object {$_ -ne 100}).Count){throw '標準縮放尚未成功設定為 100%。'}
 $result=[ordered]@{VerificationRunId=$VerificationRunId;Computer=$env:COMPUTERNAME;UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Success=$true;PreviousWidth=$values[0];PreviousHeight=$values[1];Width=$values[2];Height=$values[3];DisplayChangeResult=$values[4];LegacySystemDPI=$values[5];RequestedScalePercent=100;NativeScalePercent=$nativeScales;CustomScalingEnabled=$false;LegacyAppsMayRequireNextSignIn=$true;AppliedAt=(Get-Date).ToString('o')}
 $result|ConvertTo-Json|Set-Content (Join-Path $root $resultFileName) -Encoding UTF8
 if(-not $Worker){$result|ConvertTo-Json|Set-Content (Join-Path $PSScriptRoot $resultFileName) -Encoding UTF8}
 Write-Host ('目前主螢幕解析度：'+$result.Width+'×'+$result.Height) -ForegroundColor Green
 Write-Host '已改為標準螢幕縮放 100%，自訂縮放已關閉；少數舊程式可能需重新登入後更新。'
}catch{
 @{Success=$false;Error=$_.Exception.Message;AppliedAt=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $root $resultFileName) -Encoding UTF8
 throw
}