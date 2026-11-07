#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$VerifyOnly)
$ErrorActionPreference='Stop'
function Find-OneDrive {
 @(Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue|Where-Object {$_.DisplayName -eq 'Microsoft OneDrive'})
}
$before=@(Find-OneDrive)
if(-not $VerifyOnly){
 foreach($entry in $before){
  $command=$entry.UninstallString
  if($command -notmatch '^"([^"\r\n]+\.exe)"\s+(.+)$'){throw 'OneDrive 解除安裝命令格式不符，保留原資料並停止。'}
  $exe=$Matches[1];$arguments=$Matches[2]
  if([IO.Path]::GetFileName($exe) -ine 'OneDriveSetup.exe' -or $arguments -notmatch '(?i)/uninstall\b'){throw '不是預期的 OneDrive 解除安裝程式。'}
  $sig=Get-AuthenticodeSignature -LiteralPath $exe
  if($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation'){throw 'OneDrive 解除安裝程式簽章驗證失敗。'}
  Write-Host '正在解除安裝 OneDrive；保留同步資料夾中的個人檔案。' -ForegroundColor Cyan
  $proc=Start-Process -FilePath $exe -ArgumentList $arguments -PassThru
  if(-not $proc.WaitForExit(120000)){throw 'OneDrive 解除安裝超過兩分鐘，請稍後再執行本模組檢查。'}
  if($proc.ExitCode -notin @(0,3010)){throw ('OneDrive 解除安裝失敗：'+$proc.ExitCode)}
 }
 for($i=0;$i -lt 15 -and @(Find-OneDrive).Count;$i++){Start-Sleep -Seconds 2}
 if(@(Find-OneDrive).Count -eq 0){
  $folder=[IO.Path]::GetFullPath((Join-Path $env:USERPROFILE 'OneDrive'))
  if([IO.Path]::GetDirectoryName($folder) -ine $env:USERPROFILE.TrimEnd('\')){throw 'OneDrive 路徑不符。'}
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
}
$remaining=@(Find-OneDrive)
$processes=@(Get-Process OneDrive -ErrorAction SilentlyContinue)
$root=Join-Path $env:ProgramData 'NUC8-Setup';New-Item -ItemType Directory $root -Force|Out-Null
$result=@{Success=($remaining.Count -eq 0 -and $processes.Count -eq 0);RemainingInstallations=$remaining.Count;RunningProcesses=$processes.Count;DataFolderPreserved=(Test-Path (Join-Path $env:USERPROFILE 'OneDrive'));CheckedAt=(Get-Date).ToString('o')}
$result|ConvertTo-Json|Set-Content (Join-Path $root 'OneDrive-Result.json') -Encoding UTF8
if(-not $result.Success){throw 'OneDrive 仍安裝或執行中，請查看 OneDrive-Result.json。'}
Write-Host 'OneDrive 程式清理檢查通過；含有個人檔案的資料夾不刪除。' -ForegroundColor Green

