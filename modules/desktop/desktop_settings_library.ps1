#Requires -Version 5.1
 function Remove-SetupDesktopEntry([IO.FileSystemInfo]$Item,[string]$AllowedRoot){
  $full=[IO.Path]::GetFullPath($Item.FullName)
  $prefix=[IO.Path]::GetFullPath($AllowedRoot).TrimEnd('\')+'\'
  if(-not $full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw ('拒絕刪除桌面以外的路徑：'+$full)}
  if($Item.Attributes -band [IO.FileAttributes]::ReparsePoint){
   if($Item -is [IO.DirectoryInfo]){[IO.Directory]::Delete($full,$false)}else{[IO.File]::Delete($full)}
   return
  }
  if($Item -is [IO.DirectoryInfo]){
   foreach($child in Get-ChildItem -LiteralPath $full -Force){Remove-SetupDesktopEntry -Item $child -AllowedRoot $AllowedRoot}
   [IO.Directory]::Delete($full,$false)
  }else{Remove-Item -LiteralPath $full -Force}
 }

function Invoke-SetupDesktopSettings {
 param([Parameter(Mandatory=$true)][string]$ModuleRoot,[Parameter(Mandatory=$true)][string]$SourcePackageRoot,[Parameter(Mandatory=$true)][string[]]$DesktopRoots)
 . (Join-Path $ModuleRoot 'desktop_safety.ps1')
 Assert-DesktopSourceLocation -SourceRoot $SourcePackageRoot -DesktopRoots $DesktopRoots
 $roots=@($DesktopRoots|Select-Object -Unique)
 $deleted=New-Object Collections.Generic.List[string]
 Write-Host '清理桌面：其他一般檔案、資料夾與捷徑將直接刪除，不保留備份。' -ForegroundColor Yellow
 foreach($desktop in $roots){
  if([string]::IsNullOrWhiteSpace($desktop)){throw '無法辨識桌面路徑。'}
  $absolute=[IO.Path]::GetFullPath($desktop).TrimEnd('\')
  if($absolute -eq [IO.Path]::GetPathRoot($absolute).TrimEnd('\') -or $absolute -eq $env:USERPROFILE){throw ('桌面路徑不安全：'+$absolute)}
  foreach($item in Get-ChildItem -LiteralPath $absolute -Force -ErrorAction Stop|Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::Hidden) -and -not ($_.Attributes -band [IO.FileAttributes]::System) }){
   Write-Host ('刪除桌面項目：'+$item.FullName)
   Remove-SetupDesktopEntry -Item $item -AllowedRoot $absolute
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
  $key='HKCU:\Software\Microsoft\Windows\CurrentVersion\explorer\HideDesktopIcons\'+$panel
  if(-not(Test-Path $key)){New-Item $key -Force|Out-Null}
  foreach($id in $show){New-ItemProperty $key -Name $id -Value 0 -PropertyType DWord -Force|Out-Null}
  foreach($id in $hide){New-ItemProperty $key -Name $id -Value 1 -PropertyType DWord -Force|Out-Null}
 }
 New-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\explorer\Advanced' -Name HideIcons -Value 0 -PropertyType DWord -Force|Out-Null
 if(-not ('NUC8DesktopRefresh' -as [type])){Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public static class NUC8DesktopRefresh{[DllImport("shell32.dll")]public static extern void SHChangeNotify(int e,uint f,IntPtr a,IntPtr b);}'}
 [NUC8DesktopRefresh]::SHChangeNotify(0x08000000,0,[IntPtr]::Zero,[IntPtr]::Zero)
 $remaining=@(foreach($desktop in $roots){Get-ChildItem -LiteralPath $desktop -Force|Where-Object {-not ($_.Attributes -band [IO.FileAttributes]::Hidden) -and -not ($_.Attributes -band [IO.FileAttributes]::System)}|Select-Object -ExpandProperty FullName})
 $result=[ordered]@{Success=($remaining.Count -eq 0);DesktopRoots=$roots;DeletedItems=@($deleted.ToArray());RemainingFiles=$remaining;SystemIcons=@('控制台','本機','網路','資源回收筒');AppliedAt=(Get-Date).ToString('o')}
 return [pscustomobject]$result
}
