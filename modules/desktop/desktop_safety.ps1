#Requires -Version 5.1
function Assert-DesktopSourceLocation {
 param([Parameter(Mandatory=$true)][string]$SourceRoot,[Parameter(Mandatory=$true)][string[]]$DesktopRoots)
 if([string]::IsNullOrWhiteSpace($SourceRoot)){throw '缺少桌面清理來源套件位置，拒絕清理。'}
 $source=[IO.Path]::GetFullPath($SourceRoot).TrimEnd('\','/')
 foreach($desktopPath in $DesktopRoots){
  if([string]::IsNullOrWhiteSpace($desktopPath)){throw '無法辨識桌面路徑，拒絕清理。'}
  $desktop=[IO.Path]::GetFullPath($desktopPath).TrimEnd('\','/')
  if($source.Equals($desktop,[StringComparison]::OrdinalIgnoreCase) -or $source.StartsWith($desktop+'\',[StringComparison]::OrdinalIgnoreCase)){
   throw '工具包不可位於桌面本身或其子目錄；請先完整移至 USB 或其他非桌面位置，再執行。'
  }
 }
}