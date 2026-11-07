#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$Worker)
$ErrorActionPreference='Stop'
$root=Join-Path $env:ProgramData 'NUC8-Setup'
New-Item -ItemType Directory $root -Force|Out-Null
if(-not $Worker -and [Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0){
 $workerPath=Join-Path $root 'Desktop-Worker.ps1'
 Copy-Item -LiteralPath $PSCommandPath -Destination $workerPath -Force
 $resultPath=Join-Path $root 'Desktop-Result.json'
 if(Test-Path $resultPath){Remove-Item -LiteralPath $resultPath -Force}
 $name='NUC8-Apply-Desktop'
 $action=New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$workerPath+'" -Worker')
 $principal=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Highest
 Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -Force|Out-Null
 Start-ScheduledTask -TaskName $name
 $deadline=(Get-Date).AddSeconds(60)
 do{Start-Sleep -Seconds 2;$task=Get-ScheduledTask -TaskName $name;if(Test-Path $resultPath){break}}while((Get-Date) -lt $deadline)
 if($task.State -ne 'Running'){Unregister-ScheduledTask -TaskName $name -Confirm:$false}
 if(-not(Test-Path $resultPath)){throw '未取得桌面設定結果，請在目標帳號登入桌面後再執行。'}
 $result=Get-Content $resultPath -Raw|ConvertFrom-Json
 if($resultPath -ne (Join-Path $PSScriptRoot 'Desktop-Result.json')){Copy-Item $resultPath (Join-Path $PSScriptRoot 'Desktop-Result.json') -Force}
 $result|Format-List|Out-Host
 if(-not $result.Success){throw $result.Error}
 return
}
try{
 $roots=@([Environment]::GetFolderPath('DesktopDirectory'),[Environment]::GetFolderPath('CommonDesktopDirectory'))|Select-Object -Unique
 $deleted=New-Object Collections.Generic.List[string]
 function Remove-DesktopEntry([IO.FileSystemInfo]$Item,[string]$AllowedRoot){
  $full=[IO.Path]::GetFullPath($Item.FullName)
  $prefix=[IO.Path]::GetFullPath($AllowedRoot).TrimEnd('\')+'\'
  if(-not $full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw ('拒絕刪除桌面以外的路徑：'+$full)}
  if($Item.Attributes -band [IO.FileAttributes]::ReparsePoint){
   if($Item -is [IO.DirectoryInfo]){[IO.Directory]::Delete($full,$false)}else{[IO.File]::Delete($full)}
   return
  }
  if($Item -is [IO.DirectoryInfo]){
   foreach($child in Get-ChildItem -LiteralPath $full -Force){Remove-DesktopEntry -Item $child -AllowedRoot $AllowedRoot}
   [IO.Directory]::Delete($full,$false)
  }else{Remove-Item -LiteralPath $full -Force}
 }
 Write-Host '清理桌面：其他一般檔案、資料夾與捷徑將直接刪除，不保留備份。' -ForegroundColor Yellow
 foreach($desktop in $roots){
  if([string]::IsNullOrWhiteSpace($desktop)){throw '無法辨識桌面路徑。'}
  $absolute=[IO.Path]::GetFullPath($desktop).TrimEnd('\')
  if($absolute -eq [IO.Path]::GetPathRoot($absolute).TrimEnd('\') -or $absolute -eq $env:USERPROFILE){throw ('桌面路徑不安全：'+$absolute)}
  foreach($item in Get-ChildItem -LiteralPath $absolute -Force -ErrorAction Stop|Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::Hidden) -and -not ($_.Attributes -band [IO.FileAttributes]::System) }){
   Write-Host ('刪除桌面項目：'+$item.FullName)
   Remove-DesktopEntry -Item $item -AllowedRoot $absolute
   $deleted.Add($item.FullName)
  }
 }
 $edgeUpdate='HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate'
 if(-not(Test-Path $edgeUpdate)){New-Item $edgeUpdate -Force|Out-Null}
 New-ItemProperty $edgeUpdate -Name CreateDesktopShortcutDefault -Value 0 -PropertyType DWord -Force|Out-Null
 New-ItemProperty $edgeUpdate -Name RemoveDesktopShortcutDefault -Value 2 -PropertyType DWord -Force|Out-Null
 $show=@('{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}','{20D04FE0-3AEA-1069-A2D8-08002B30309D}','{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}','{645FF040-5081-101B-9F08-00AA002F954E}')
 $hide=@('{59031a47-3f72-44a7-89c5-5595fe6b30ee}','{031E4825-7B94-4dc3-B131-E946B44C8DD5}','{B4FB3F98-C1EA-428d-A78A-D1F5659CBA93}','{2cc5ca98-6485-489a-920e-b3e88a6ccce3}')
 foreach($panel in @('NewStartPanel','ClassicStartMenu')){
  $key='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\'+$panel
  if(-not(Test-Path $key)){New-Item $key -Force|Out-Null}
  foreach($id in $show){New-ItemProperty $key -Name $id -Value 0 -PropertyType DWord -Force|Out-Null}
  foreach($id in $hide){New-ItemProperty $key -Name $id -Value 1 -PropertyType DWord -Force|Out-Null}
 }
 New-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name HideIcons -Value 0 -PropertyType DWord -Force|Out-Null
 Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class NUC8DesktopRefresh{[DllImport("shell32.dll")]public static extern void SHChangeNotify(int e,uint f,IntPtr a,IntPtr b);}'
 [NUC8DesktopRefresh]::SHChangeNotify(0x08000000,0,[IntPtr]::Zero,[IntPtr]::Zero)
 $remaining=@(foreach($desktop in $roots){Get-ChildItem -LiteralPath $desktop -Force|Where-Object {-not ($_.Attributes -band [IO.FileAttributes]::Hidden) -and -not ($_.Attributes -band [IO.FileAttributes]::System)}|Select-Object -ExpandProperty FullName})
 $result=[ordered]@{Success=($remaining.Count -eq 0);DesktopRoots=$roots;DeletedItems=@($deleted.ToArray());RemainingFiles=$remaining;SystemIcons=@('控制台','本機','網路','資源回收筒');AppliedAt=(Get-Date).ToString('o')}
 $result|ConvertTo-Json -Depth 5|Set-Content (Join-Path $root 'Desktop-Result.json') -Encoding UTF8
 if((Join-Path $PSScriptRoot 'Desktop-Result.json') -ne (Join-Path $root 'Desktop-Result.json')){$result|ConvertTo-Json -Depth 5|Set-Content (Join-Path $PSScriptRoot 'Desktop-Result.json') -Encoding UTF8}
 Write-Host '桌面已清理，僅保留四個指定系統圖示。' -ForegroundColor Green
}catch{
 @{Success=$false;Error=$_.Exception.Message;FailedAt=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $root 'Desktop-Result.json') -Encoding UTF8
 throw
}