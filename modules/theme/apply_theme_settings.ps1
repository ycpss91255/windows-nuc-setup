#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$Worker,[switch]$VerifyOnly,[ValidatePattern('^[a-fA-F0-9-]{36}$')][string]$VerificationRunId)
$ErrorActionPreference='Stop'
$resultFileName=if($VerifyOnly){'Theme-Verification.json'}else{'Theme-Result.json'}
$root=Join-Path $env:ProgramData 'NUC8-Setup'
New-Item -ItemType Directory $root -Force|Out-Null
if(-not $Worker -and [Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0){
 $workerPath=Join-Path $root 'Theme-Worker.ps1'
 . (Join-Path $PSScriptRoot '../native/managed_source_library.ps1')
 $null=Copy-SetupManagedSource -SourceRoot $PSScriptRoot -DestinationRoot $root -FileName 'theme.cs'
 Copy-Item $PSCommandPath $workerPath -Force
 $resultPath=Join-Path $root $resultFileName
 if(Test-Path $resultPath){Remove-Item $resultPath -Force}
 $name='NUC8-Apply-Theme'
 $workerArgs='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$workerPath+'" -Worker'
 if($VerifyOnly){$workerArgs+=' -VerifyOnly'}
 if($VerificationRunId){$workerArgs+=' -VerificationRunId '+$VerificationRunId}
 $action=New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument $workerArgs
 $principal=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Highest
 Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -Force|Out-Null
 Start-ScheduledTask -TaskName $name
 $deadline=(Get-Date).AddSeconds(60)
 do{Start-Sleep -Seconds 2;$task=Get-ScheduledTask -TaskName $name;if(Test-Path $resultPath){break}}while((Get-Date) -lt $deadline)
 if($task.State -ne 'Running'){Unregister-ScheduledTask -TaskName $name -Confirm:$false}
 if(-not(Test-Path $resultPath)){throw '未取得桌面配色設定結果，請先登入桌面。'}
 $result=Get-Content $resultPath -Raw|ConvertFrom-Json
 if($resultPath -ne (Join-Path $PSScriptRoot $resultFileName)){Copy-Item $resultPath (Join-Path $PSScriptRoot $resultFileName) -Force}
 $result|Format-List|Out-Host
 if(-not $result.Success){throw $result.Error}
 return
}
try{
 $personalize='HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
 if(-not $VerifyOnly){
 if(-not(Test-Path $personalize)){New-Item $personalize -Force|Out-Null}
 New-ItemProperty $personalize -Name AppsUseLightTheme -Value 0 -PropertyType DWord -Force|Out-Null
 New-ItemProperty $personalize -Name SystemUsesLightTheme -Value 0 -PropertyType DWord -Force|Out-Null
 Set-ItemProperty 'HKCU:\Control Panel\Colors' -Name Background -Value '0 0 0'
 Set-ItemProperty 'HKCU:\Control Panel\Desktop' -Name Wallpaper -Value ''
 $wallpapers='HKCU:\Software\Microsoft\Windows\CurrentVersion\explorer\Wallpapers'
 if(-not(Test-Path $wallpapers)){New-Item $wallpapers -Force|Out-Null}
 New-ItemProperty $wallpapers -Name BackgroundType -Value 1 -PropertyType DWord -Force|Out-Null
 $cloud='HKCU:\Software\Policies\Microsoft\Windows\CloudContent'
 if(-not(Test-Path $cloud)){New-Item $cloud -Force|Out-Null}
 New-ItemProperty $cloud -Name DisableSpotlightCollectionOnDesktop -Value 1 -PropertyType DWord -Force|Out-Null
 }
Add-Type -Path (Join-Path $PSScriptRoot 'native/theme.cs')
 if(-not $VerifyOnly){
 if(-not [NUC8Theme]::SetSysColors(1,@(1),@([uint32]0))){throw '無法設定桌面背景顏色。'}
 if(-not [NUC8Theme]::SystemParametersInfo(20,0,'',3)){throw '無法移除桌面背景圖片。'}
 $unused=[IntPtr]::Zero
 [void][NUC8Theme]::SendMessageTimeout([IntPtr]0xffff,0x1a,[IntPtr]::Zero,'ImmersiveColorSet',2,2000,[ref]$unused)
 }
 $shellReloaded=$false
 $taskbarColor=[NUC8Theme]::TaskbarColor()
 $taskbarDark=($taskbarColor[0]+$taskbarColor[1]+$taskbarColor[2])/3 -lt 128
 if(-not $VerifyOnly -and -not $taskbarDark){
  Write-Host '工作列仍為淺色，正在重新載入檔案總管；不會重新開機。' -ForegroundColor Cyan
  $sessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId
  Get-Process explorer -ErrorAction SilentlyContinue|Where-Object SessionId -eq $sessionId|Stop-Process -Force
  $shellReloaded=$true
  Start-Sleep -Seconds 3
  if(-not @(Get-Process explorer -ErrorAction SilentlyContinue|Where-Object SessionId -eq $sessionId).Count){Start-Process explorer.exe}
  for($attempt=0;$attempt -lt 20;$attempt++){
   Start-Sleep -Milliseconds 500
   try{$taskbarColor=[NUC8Theme]::TaskbarColor();$taskbarDark=($taskbarColor[0]+$taskbarColor[1]+$taskbarColor[2])/3 -lt 128;if($taskbarDark){break}}catch{}
  }
 }
 $wallpaper=New-Object Text.StringBuilder 1024
 [void][NUC8Theme]::ReadWallpaper(0x73,1024,$wallpaper,0)
 $theme=Get-ItemProperty $personalize
 $actualColor=[NUC8Theme]::GetSysColor(1)
 $result=[ordered]@{VerificationRunId=$VerificationRunId;Computer=$env:COMPUTERNAME;UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Success=($theme.AppsUseLightTheme -eq 0 -and $theme.SystemUsesLightTheme -eq 0 -and $actualColor -eq 0 -and $wallpaper.Length -eq 0 -and $taskbarDark);AppsMode=$(if($theme.AppsUseLightTheme -eq 0){'Dark'}else{'Light'});WindowsMode=$(if($theme.SystemUsesLightTheme -eq 0){'Dark'}else{'Light'});Background='#000000';TaskbarRGB=@($taskbarColor);TaskbarIsDark=$taskbarDark;ExplorerReloaded=$shellReloaded;ActualBackgroundColor=$actualColor;ActualWallpaper=$wallpaper.ToString();AppliedAt=(Get-Date).ToString('o')}
 $result|ConvertTo-Json|Set-Content (Join-Path $root $resultFileName) -Encoding UTF8
 if((Join-Path $PSScriptRoot $resultFileName) -ne (Join-Path $root $resultFileName)){$result|ConvertTo-Json|Set-Content (Join-Path $PSScriptRoot $resultFileName) -Encoding UTF8}
 if($VerifyOnly){Write-Host '配色與背景即時驗證完成。' -ForegroundColor Green}else{Write-Host 'Windows/應用程式深色模式、純黑色桌面背景已套用。' -ForegroundColor Green}
 if(-not $result.Success){throw '配色或背景的即時驗證未通過。'}
}catch{
 @{Success=$false;Error=$_.Exception.Message;FailedAt=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $root $resultFileName) -Encoding UTF8
 throw
}