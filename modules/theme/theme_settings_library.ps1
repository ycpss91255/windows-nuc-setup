#Requires -Version 5.1
# Definitions only; current-user and native changes run only in the named leaf.
function Invoke-SetupThemeSettings {
 param([Parameter(Mandatory=$true)][string]$ModuleRoot,[switch]$VerifyOnly)
 $ErrorActionPreference='Stop'
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
 if(-not ('NUC8Theme' -as [type])){Add-Type -Path (Join-Path $ModuleRoot 'native/theme.cs')}
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
  $sessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId
  Get-Process explorer -ErrorAction SilentlyContinue|Where-Object SessionId -eq $sessionId|Stop-Process -Force
  $shellReloaded=$true
  Start-Sleep -Seconds 3
  if(-not @(Get-Process explorer -ErrorAction SilentlyContinue|Where-Object SessionId -eq $sessionId).Count){Start-Process -FilePath (Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::Windows)) 'explorer.exe')}
  for($attempt=0;$attempt -lt 20;$attempt++){
   Start-Sleep -Milliseconds 500
   try{$taskbarColor=[NUC8Theme]::TaskbarColor();$taskbarDark=($taskbarColor[0]+$taskbarColor[1]+$taskbarColor[2])/3 -lt 128;if($taskbarDark){break}}catch{}
  }
 }
 $wallpaper=New-Object Text.StringBuilder 1024
 if(-not [NUC8Theme]::ReadWallpaper(0x73,1024,$wallpaper,0)){throw '無法讀取桌面背景圖片，未確認目前桌布。'}
 $theme=Get-ItemProperty $personalize
 $actualColor=[NUC8Theme]::GetSysColor(1)
 $result=[ordered]@{Success=($theme.AppsUseLightTheme -eq 0 -and $theme.SystemUsesLightTheme -eq 0 -and $actualColor -eq 0 -and $wallpaper.Length -eq 0 -and $taskbarDark);AppsMode=$(if($theme.AppsUseLightTheme -eq 0){'Dark'}else{'Light'});WindowsMode=$(if($theme.SystemUsesLightTheme -eq 0){'Dark'}else{'Light'});Background='#000000';TaskbarRGB=@($taskbarColor);TaskbarIsDark=$taskbarDark;ExplorerReloaded=$shellReloaded;ActualBackgroundColor=$actualColor;ActualWallpaper=$wallpaper.ToString();AppliedAt=(Get-Date).ToString('o')}
 if(-not $result.Success){throw '配色或背景的即時驗證未通過。'}
 return [pscustomobject]$result
}
