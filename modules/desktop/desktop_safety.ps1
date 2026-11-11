#Requires -Version 5.1
function Get-DesktopSafeLongDirectory {
 param([Parameter(Mandatory=$true)][string]$Path)
 $item=Get-Item -LiteralPath ([IO.Path]::GetFullPath($Path)) -Force -ErrorAction Stop
 if(-not $item.PSIsContainer){throw '桌面安全檢查要求既有資料夾，拒絕清理。'}
 # Windows FileSystem provider expands 8.3 names. Inspect every lexical ancestor
 # before using that long path; a junction above the leaf must not hide the source.
 $longPath=$item.FullName
 while($null -ne $item){
  if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw '套件或桌面路徑包含重新解析點；請改用實際資料夾位置，拒絕清理。'}
  $parent=$item.Parent
  if($null -eq $parent){break}
  $item=Get-Item -LiteralPath $parent.FullName -Force -ErrorAction Stop
 }
 return $longPath.TrimEnd('\','/')
}
function Assert-DesktopSourceLocation {
 param([Parameter(Mandatory=$true)][string]$SourceRoot,[Parameter(Mandatory=$true)][string[]]$DesktopRoots)
 if([string]::IsNullOrWhiteSpace($SourceRoot)){throw '缺少桌面清理來源套件位置，拒絕清理。'}
 $source=Get-DesktopSafeLongDirectory -Path $SourceRoot
 foreach($desktopPath in $DesktopRoots){
  if([string]::IsNullOrWhiteSpace($desktopPath)){throw '無法辨識桌面路徑，拒絕清理。'}
  $desktop=Get-DesktopSafeLongDirectory -Path $desktopPath
  if($source.Equals($desktop,[StringComparison]::OrdinalIgnoreCase) -or $source.StartsWith($desktop+'\',[StringComparison]::OrdinalIgnoreCase)){
   throw '工具包不可位於桌面本身或其子目錄；請先完整移至 USB 或其他非桌面位置，再執行。'
  }
 }
}