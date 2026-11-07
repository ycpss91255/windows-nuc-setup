#Requires -Version 5.1
param([switch]$VerifyOnly)
$ErrorActionPreference='Stop'
$sshRoot=Join-Path $env:USERPROFILE '.ssh'
$config=Join-Path $sshRoot 'config'
$sites=Join-Path $sshRoot 'active-sites.conf'
$fragments=Join-Path $sshRoot 'config.d'
if(-not $VerifyOnly){
 foreach($directory in @($sshRoot,$fragments)){
  if(-not(Test-Path -LiteralPath $directory)){New-Item -ItemType Directory -Path $directory|Out-Null}
  elseif(-not(Test-Path -LiteralPath $directory -PathType Container)){throw ('此路徑不是資料夾：'+$directory)}
 }
 [IO.File]::SetAttributes($sshRoot,([IO.File]::GetAttributes($sshRoot) -bor [IO.FileAttributes]::Hidden))
 $readme=Join-Path $sshRoot 'readme.md'
 if(-not(Test-Path -LiteralPath $readme)){Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'custom_hosts_sync\ssh_readme.md') -Destination $readme}
 $encoding=New-Object Text.UTF8Encoding($false)
 if(-not(Test-Path -LiteralPath $sites)){
  [IO.File]::WriteAllText($sites,"# No sites configured yet. Network-based site synchronization is not installed.`r`n",$encoding)
 }
 if(-not(Test-Path -LiteralPath $config)){
  [IO.File]::WriteAllText($config,"# SSH client configuration for the current user.`r`n# Relative paths are resolved under this user's .ssh directory.`r`nInclude active-sites.conf`r`n`r`n# Add explicit Host entries below when needed.`r`n",$encoding)
 }else{Write-Host '保留既有 .ssh\config，不覆寫或變更連線設定。'}
}
$success=(Test-Path -LiteralPath $sshRoot -PathType Container) -and (Test-Path -LiteralPath $fragments -PathType Container) -and (Test-Path -LiteralPath $config -PathType Leaf) -and (Test-Path -LiteralPath $sites -PathType Leaf)
if(-not(Test-Path -LiteralPath (Join-Path $sshRoot 'readme.md') -PathType Leaf)){throw '.ssh\readme.md 說明檔不存在。'}
if(-not $success){throw 'SSH 客戶端目錄或設定檔尚未完整建立。'}
if(([IO.File]::GetAttributes($sshRoot) -band [IO.FileAttributes]::Hidden) -eq 0){throw '.ssh 尚未設為 Windows 隱藏資料夾。'}
Write-Host ('SSH 客戶端目錄已確認：'+$sshRoot) -ForegroundColor Green
Write-Host '已備妥 config、active-sites.conf、config.d；未產生金鑰或加入主機。'


