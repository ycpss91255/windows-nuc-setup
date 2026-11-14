#Requires -Version 5.1
function Get-OneDriveRemovalState {
 $ErrorActionPreference='Stop'
 $entries=@(foreach($root in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')){
  if(Test-Path -LiteralPath $root -ErrorAction Stop){
   foreach($key in @(Get-ChildItem -LiteralPath $root -ErrorAction Stop)){
    $item=Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
    if($item.DisplayName -eq 'Microsoft OneDrive'){$item}
   }
  }
 })
 $locations=@((Join-Path $env:LOCALAPPDATA 'Microsoft/OneDrive/OneDrive.exe'),(Join-Path $env:ProgramFiles 'Microsoft OneDrive/OneDrive.exe'))
 if(${env:ProgramFiles(x86)}){$locations+=(Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive/OneDrive.exe')}
 $present=@($locations|Select-Object -Unique|Where-Object {Test-Path -LiteralPath $_ -PathType Leaf -ErrorAction Stop})
 $processes=@(Get-Process -ErrorAction Stop|Where-Object ProcessName -eq 'OneDrive')
 return [pscustomobject]@{Entries=$entries;ExecutableCount=$present.Count;ProcessCount=$processes.Count;VerifiedAbsent=($entries.Count -eq 0 -and $present.Count -eq 0 -and $processes.Count -eq 0)}
}
function Invoke-OneDriveRemoval {
 param([switch]$VerifyOnly)
 $ErrorActionPreference='Stop'
 $state=Get-OneDriveRemovalState
 $codes=New-Object 'Collections.Generic.List[int]'
 if(-not $VerifyOnly){
  foreach($entry in @($state.Entries)){
   if($entry.UninstallString -notmatch '^"([^"\r\n]+\.exe)"\s+(.+)$'){throw 'OneDrive 解除安裝命令格式不符，保留原資料並停止。'}
   $exe=$Matches[1];$arguments=$Matches[2]
   if([IO.Path]::GetFileName($exe) -ine 'OneDriveSetup.exe' -or $arguments -notmatch '(?i)/uninstall\b'){throw '不是預期的 OneDrive 解除安裝程式。'}
   $signature=Get-AuthenticodeSignature -LiteralPath $exe -ErrorAction Stop
   if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(^|,\s*)O=Microsoft Corporation(,|$)'){throw 'OneDrive 解除安裝程式簽章驗證失敗。'}
   Write-Host '正在解除安裝 OneDrive；將以實際安裝紀錄、執行檔及程序確認結果，保留個人同步資料。' -ForegroundColor Cyan
   $process=Start-Process -FilePath $exe -ArgumentList $arguments -PassThru
   if(-not $process.WaitForExit(120000)){throw 'OneDrive 解除安裝超過兩分鐘，請稍後重試檢查；未宣告成功。'}
   $codes.Add([int]$process.ExitCode)
   $state=Get-OneDriveRemovalState
   if($state.VerifiedAbsent){break}
  }
  for($i=0;$i -lt 15 -and -not $state.VerifiedAbsent;$i++){Start-Sleep -Seconds 2;$state=Get-OneDriveRemovalState}
 }
 return [ordered]@{Success=[bool]$state.VerifiedAbsent;VerifiedAbsent=[bool]$state.VerifiedAbsent;ExitCodes=@($codes.ToArray());RemainingInstallations=@($state.Entries).Count;RemainingExecutables=$state.ExecutableCount;RunningProcesses=$state.ProcessCount;CheckedAt=(Get-Date).ToString('o')}
}
function Invoke-OneDriveRemovalEntry {
 param([switch]$VerifyOnly)
 $ErrorActionPreference='Stop'
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
}
