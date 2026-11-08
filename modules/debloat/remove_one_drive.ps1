#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$VerifyOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'one_drive_library.ps1')
$root=Join-Path $env:ProgramData 'NUC8-Setup'
New-Item -ItemType Directory $root -Force|Out-Null
try{
 $result=Invoke-OneDriveRemoval -VerifyOnly:$VerifyOnly
}catch{
 @{Success=$false;VerifiedAbsent=$false;Error=$_.Exception.Message;CheckedAt=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $root 'OneDrive-Result.json') -Encoding UTF8
 throw
}
if($result.Success -and -not $VerifyOnly){
  $rawProfile=$env:USERPROFILE
  $profile=[IO.Path]::GetFullPath($rawProfile).TrimEnd('\','/')
  $profileRoot=[IO.Path]::GetPathRoot($profile).TrimEnd('\','/')
  if($rawProfile -notmatch '^(?:[A-Za-z]:[\\/]|\\\\[^\\]+\\[^\\]+(?:\\|$))' -or $profile -ieq $profileRoot){throw ('OneDrive 路徑不符。raw='+$rawProfile+'; canonical='+$profile+'; root='+$profileRoot)}
  $folder=[IO.Path]::GetFullPath((Join-Path $profile 'OneDrive'))
  $parent=[IO.Path]::GetFullPath([IO.Path]::GetDirectoryName($folder)).TrimEnd('\','/')
  if($parent -ine $profile){throw ('OneDrive 路徑不符。raw='+$rawProfile+'; canonical='+$profile+'; parent='+$parent)}
  if(Test-Path -LiteralPath $folder -PathType Container){
   $item=Get-Item -LiteralPath $folder -Force
   if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0){
    $children=@(Get-ChildItem -LiteralPath $folder -Force)
    if(@($children|Where-Object {$_.PSIsContainer -or $_.Name -ine 'desktop.ini' -or ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)}).Count -eq 0){
     foreach($child in $children){Remove-Item -LiteralPath $child.FullName -Force}
     [IO.File]::SetAttributes($folder,([IO.File]::GetAttributes($folder) -band (-bnot [IO.FileAttributes]::ReadOnly)))
     [IO.Directory]::Delete($folder,$false)
    }else{Write-Host 'OneDrive 資料夾含有檔案，已保留。'}
   }
  }
}
$result.DataFolderPreserved=Test-Path -LiteralPath (Join-Path $env:USERPROFILE 'OneDrive')
$result|ConvertTo-Json|Set-Content (Join-Path $root 'OneDrive-Result.json') -Encoding UTF8
if(-not $result.Success){throw 'OneDrive 安裝紀錄、執行檔或程序仍存在，尚未確認移除；請查看 OneDrive-Result.json。'}
Write-Host 'OneDrive 程式清理檢查通過；含有個人檔案的資料夾不刪除。' -ForegroundColor Green
