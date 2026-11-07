#Requires -Version 5.1
$ErrorActionPreference='Stop'
$package=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('windows_ssh_client_'+[guid]::NewGuid().ToString('N'))
$module=Join-Path $fixture "USB ' 中文\modules\ssh"
$source=Join-Path $package 'modules\ssh'
New-Item -ItemType Directory (Join-Path $module 'custom_hosts_sync') -Force|Out-Null
Copy-Item -LiteralPath (Join-Path $source 'initialize_ssh_client.ps1') -Destination $module
Copy-Item -LiteralPath (Join-Path $source 'custom_hosts_sync\ssh_readme.md') -Destination (Join-Path $module 'custom_hosts_sync')
$entry=Join-Path $module 'initialize_ssh_client.ps1'
$oldProfile=$env:USERPROFILE
try{
 foreach($user in @('new_user_a',"另一使用者 ' b")){
  $env:USERPROFILE=Join-Path $fixture $user
  New-Item -ItemType Directory $env:USERPROFILE|Out-Null
  & $entry
  $ssh=Join-Path $env:USERPROFILE '.ssh'
  Assert (Test-Path -LiteralPath (Join-Path $ssh 'readme.md') -PathType Leaf) ('首次執行複製說明至目前使用者：'+$user)
  Assert ((Get-FileHash -LiteralPath (Join-Path $ssh 'readme.md')).Hash -eq (Get-FileHash -LiteralPath (Join-Path $module 'custom_hosts_sync\ssh_readme.md')).Hash) ('說明內容來自可攜套件正確子目錄：'+$user)
  Assert ((Test-Path -LiteralPath (Join-Path $ssh 'config.d') -PathType Container) -and (Test-Path -LiteralPath (Join-Path $ssh 'active-sites.conf') -PathType Leaf)) ('首次執行建立完整 SSH 結構：'+$user)
  Assert (([IO.File]::GetAttributes($ssh) -band [IO.FileAttributes]::Hidden) -ne 0) ('SSH 資料夾依設定隱藏：'+$user)
  $config=Join-Path $ssh 'config'
  $custom="Include active-sites.conf`r`nHost fixture_alias`r`n HostName fixture.invalid`r`n"
  [IO.File]::WriteAllText($config,$custom,[Text.UTF8Encoding]::new($false))
  & $entry
  Assert ([IO.File]::ReadAllText($config) -ceq $custom) ('重跑保留既有使用者設定：'+$user)
  $before=@(Get-ChildItem $ssh -Recurse -Force -File|ForEach-Object {(Get-FileHash -LiteralPath $_.FullName).Hash}) -join ','
  & $entry -VerifyOnly
  $after=@(Get-ChildItem $ssh -Recurse -Force -File|ForEach-Object {(Get-FileHash -LiteralPath $_.FullName).Hash}) -join ','
  Assert ($before -ceq $after) ('VerifyOnly 確認完整且不寫入：'+$user)
 }
}finally{$env:USERPROFILE=$oldProfile}
Assert ($env:USERPROFILE -ceq $oldProfile) '測試結束還原程序環境，不使用實際使用者 SSH 目錄'
