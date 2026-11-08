#Requires -Version 5.1
function Invoke-SetupResidueCleanup {
 param(
  [Parameter(Mandatory=$true)][string]$SystemRoot,
  [Parameter(Mandatory=$true)][string]$UserProfile,
  [Parameter(Mandatory=$true)][string]$ResultRoot,
  [Parameter(Mandatory=$true)][string]$UserSid,
  [switch]$VerifyOnly
 )
 $ErrorActionPreference='Stop'
 $SystemRoot=[IO.Path]::GetFullPath($SystemRoot)
 $UserProfile=[IO.Path]::GetFullPath($UserProfile)
 if($UserProfile.TrimEnd('\') -eq [IO.Path]::GetPathRoot($UserProfile).TrimEnd('\')){throw '使用者資料夾不能是磁碟根目錄。'}
 foreach($base in @($SystemRoot,$UserProfile)){
  if(-not(Test-Path -LiteralPath $base -PathType Container)){throw "清理根目錄不存在：$base"}
  $ancestor=Get-Item -LiteralPath $base -Force
  while($null -ne $ancestor){
   if(($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw '清理根目錄不可經過重新解析點。'}
   $ancestor=$ancestor.Parent
  }
 }
 $root=[IO.Path]::GetFullPath($ResultRoot)
 New-Item -ItemType Directory $root -Force|Out-Null
$results=@()
$targets=@((Join-Path $SystemRoot 'Windows.old'))
foreach($name in @('Contacts','Saved Games','Favorites','Links','Searches')){$targets+=Join-Path $UserProfile $name}
foreach($target in $targets){
 $full=[IO.Path]::GetFullPath($target)
 $parent=[IO.Path]::GetDirectoryName($full).TrimEnd('\')
 $expected=if([IO.Path]::GetFileName($full) -eq 'Windows.old'){$SystemRoot.TrimEnd('\')}else{$UserProfile.TrimEnd('\')}
 if($parent -ine $expected){throw "清理路徑不符合範圍：$full"}
 if(-not(Test-Path -LiteralPath $full)){$results+=@{Path=$full;Status='Absent'};continue}
 $item=Get-Item -LiteralPath $full -Force
 if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){$results+=@{Path=$full;Status='PreservedReparsePoint'};continue}
 # Remove only named Windows default shortcuts/search definitions, never their targets.
 if(-not $VerifyOnly){
  $leaf=[IO.Path]::GetFileName($full)
  $defaults=switch($leaf){
   'Favorites' {@('Bing.url')}
   'Links' {@('Desktop.lnk','Downloads.lnk')}
   'Searches' {@('Everywhere.search-ms','Indexed Locations.search-ms',('winrt--{'+$UserSid+'}-.searchconnector-ms'))}
   default {@()}
  }
  foreach($name in $defaults){
   $path=Join-Path $full $name
   if(Test-Path -LiteralPath $path -PathType Leaf){
    $entry=Get-Item -LiteralPath $path -Force
    if(($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0){Remove-Item -LiteralPath $path -Force -ErrorAction Stop;Write-Host "移除預設捷徑/搜尋定義：$path"}
   }
  }
  if($leaf -eq 'Favorites'){
   $sub=Join-Path $full 'Links'
   if(Test-Path -LiteralPath $sub -PathType Container){
    $entry=Get-Item -LiteralPath $sub -Force
    if(($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0){
     $items=@(Get-ChildItem -LiteralPath $sub -Force)
     if(@($items|Where-Object {$_.PSIsContainer -or $_.Name -ine 'desktop.ini' -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)}).Count -eq 0){
      foreach($i in $items){Remove-Item -LiteralPath $i.FullName -Force}
      [IO.File]::SetAttributes($sub,([IO.File]::GetAttributes($sub) -band (-bnot [IO.FileAttributes]::ReadOnly)))
      [IO.Directory]::Delete($sub,$false)
     }
    }
   }
  }
 }
 $children=@(Get-ChildItem -LiteralPath $full -Force -ErrorAction Stop)
 $onlyMetadata=@($children|Where-Object {$_.PSIsContainer -or $_.Name -ine 'desktop.ini' -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)}).Count -eq 0
 if(-not $onlyMetadata){Write-Host "保留含有資料的資料夾：$full" -ForegroundColor Yellow;$results+=@{Path=$full;Status='PreservedData'};continue}
 if($VerifyOnly){$results+=@{Path=$full;Status='EmptyResidue'};continue}
 Write-Host "清理空資料夾：$full" -ForegroundColor Cyan
 foreach($child in $children){Remove-Item -LiteralPath $child.FullName -Force -ErrorAction Stop}
 # Nonrecursive delete fails safely if any new content appears.
 [IO.File]::SetAttributes($full,([IO.File]::GetAttributes($full) -band (-bnot [IO.FileAttributes]::ReadOnly)))
 [IO.Directory]::Delete($full,$false)
 $results+=@{Path=$full;Status='Removed'}
}
$success=@($results|Where-Object Status -eq 'EmptyResidue').Count -eq 0
@{Success=$success;CheckedAt=(Get-Date).ToString('o');Items=$results}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $root 'Residue-Result.json') -Encoding UTF8
$results|ForEach-Object {[pscustomobject]$_}|Format-Table -AutoSize
if(-not $success){throw '仍有可清除的空資料夾。'}
Write-Host '清理完成；含有實際資料的資料夾會保留並列入紀錄。' -ForegroundColor Green



}
