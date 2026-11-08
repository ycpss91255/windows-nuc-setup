#Requires -Version 5.1
. (Join-Path $PSScriptRoot 'custom_hosts_sync/sync_custom_hosts.ps1')
function Invoke-HostsSyncSshClient {
 param([Parameter(Mandatory=$true)][string]$ProfilePath)
 if([IO.Path]::GetFullPath($ProfilePath).TrimEnd('\') -ine [IO.Path]::GetFullPath($env:USERPROFILE).TrimEnd('\')){throw 'SSH 初始化使用者家目錄不符合目前帳號。'}
 & (Join-Path $PSScriptRoot 'initialize_ssh_client.ps1')
}
function Invoke-SetupHostsSync {
 param(
  [Parameter(Mandatory=$true)][string]$RuntimeRoot,
  [Parameter(Mandatory=$true)][string]$ProfilePath,
  [Parameter(Mandatory=$true)]$UserIdentity,
  [Parameter(Mandatory=$true)][string]$WindowsRoot,
  [switch]$VerifyOnly,[switch]$SyncOnly,
  [ValidateSet('All','Hosts','SSH')][string]$Mode='All'
 )
$ErrorActionPreference='Stop'
$root=$RuntimeRoot
$source=Join-Path $PSScriptRoot 'custom_hosts_sync'
$runtimePath=Join-Path $root 'runtime.json'
$taskName='CustomHostsSync'
$identity=$UserIdentity
$sid=$identity.User.Value
$profile=[IO.Path]::GetFullPath($ProfilePath).TrimEnd('\')
$actualProfile=[Environment]::ExpandEnvironmentVariables((Get-ItemProperty ('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\'+$sid)).ProfileImagePath)
if([IO.Path]::GetFullPath($actualProfile).TrimEnd('\') -ine $profile){throw '目前帳號 SID 與使用者家目錄不一致。'}

Assert-SyncPlainPath $root
Assert-SyncPlainPath $profile
if(Test-Path -LiteralPath $runtimePath){
 $owner=[IO.File]::ReadAllText($runtimePath)|ConvertFrom-Json
 if($owner.OwnerSID -ne $sid -or [IO.Path]::GetFullPath($owner.ProfilePath).TrimEnd('\') -ine $profile){throw '此電腦已由另一個帳號管理 CustomHostsSync；為避免兩個帳號互相覆寫 hosts，本次未接管。'}
}elseif((Test-Path -LiteralPath $root) -and @(Get-ChildItem -LiteralPath $root -Force).Count){throw '已有其他版本的 CustomHostsSync 資料但沒有本工具的 owner 紀錄，請先遷移，不能直接覆寫。'}

function Test-InstalledHostsSync {
 if(-not(Test-Path -LiteralPath $runtimePath)){throw 'CustomHostsSync 尚未安裝。'}
 $task=Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
 if($task.State -ne 'Running'){throw 'CustomHostsSync 背景工作未執行。'}
 $statusPath=Join-Path $root 'status.json'
 $status=[IO.File]::ReadAllText($statusPath)|ConvertFrom-Json
 $configPath=Join-Path $profile '.config\hosts\sites.json'
 $config=[IO.File]::ReadAllText($configPath)|ConvertFrom-Json
 Assert-NetworkSiteConfiguration $config
 if(Test-Path (Join-Path $root 'watcher-fatal-error.json')){throw '同步程式有啟動錯誤，請查看 watcher-fatal-error.json。'}
 $selected=if($Mode -eq 'All'){@('Hosts','SSH')}else{@($Mode)}
 foreach($name in $selected){
  $enabled=if($config.Outputs){[bool]$config.Outputs.$name}else{$true}
  if(-not $enabled){Write-Host ($name+' 輸出已停用；不檢查或改動此輸出。');continue}
  $part=$status.Outputs.$name
  if(-not $part -or -not $part.Success -or (Get-Date)-[datetime]$part.CheckedAt -gt [TimeSpan]::FromSeconds([math]::Max(45,([int]$config.PollSeconds*3)))){throw ($name+' 同步未成功或狀態過期：'+$part.Error)}
  if((Get-CustomHostsSourceDigest -ProfilePath $profile -Mode $name) -ne $part.SourceDigest){throw ($name+' 來源已變更，背景同步尚未收斂；請稍後再驗證。')}
  $output=if($name -eq 'Hosts'){Join-Path $WindowsRoot 'System32\drivers\etc\hosts'}else{Join-Path $profile '.ssh\active-sites.conf'}
  Assert-SyncPlainPath $output
  if((Get-FileHash -LiteralPath $output).Hash -ne $part.OutputHash){throw ($name+' 輸出檔已變更，背景同步尚未收斂。')}
  foreach($warning in $part.Warnings){Write-Warning $warning}
 }
 if((Get-Item -LiteralPath (Join-Path $profile '.config') -Force).Attributes -band [IO.FileAttributes]::Hidden){}else{throw '.config 目錄尚未設為隱藏。'}
 if(-not(Test-Path -LiteralPath (Join-Path $profile '.config\hosts\readme.md') -PathType Leaf)){throw '.config\hosts\readme.md 說明檔不存在。'}
 Write-Host ('選取的自動匯入輸出正常；目前站點：'+(@($status.ActiveSites) -join ', ')) -ForegroundColor Green
 foreach($warning in $status.Warnings){Write-Warning $warning}
}
if($VerifyOnly){Test-InstalledHostsSync;return}
if($SyncOnly){
 if(-not(Test-Path -LiteralPath $runtimePath)){throw '請先執行 apply_hosts_sync.cmd 安裝框架。'}
 $task=Get-ScheduledTask -TaskName $taskName -ErrorAction Stop
 Stop-ScheduledTask -TaskName $taskName
 for($i=0;$i -lt 20 -and (Get-ScheduledTask -TaskName $taskName).State -eq 'Running';$i++){Start-Sleep -Milliseconds 500}
 if((Get-ScheduledTask -TaskName $taskName).State -eq 'Running'){throw '背景工作仍執行中，本次未開始單次同步。'}
 try{
  $one=Invoke-CustomHostsSync -ProfilePath $profile -StatePath $root -TargetHostsPath (Join-Path $WindowsRoot 'System32\drivers\etc\hosts') -Mode $Mode
  if(-not $one.Success){throw ('所選輸出同步失敗，查看 '+(Join-Path $root 'status.json'))}
  Write-Host ($Mode+' 單次同步完成。') -ForegroundColor Green
 }finally{Start-ScheduledTask -TaskName $taskName}
 return
}
if($Mode -ne 'All'){throw '安裝時請使用 sites.json 的 Outputs 選擇啟用項目；-Mode 僅用於單次同步或驗證。'}

$dataRoot=Join-Path $profile '.config\hosts'
$hostSources=Join-Path $dataRoot 'hosts.d'
$sshSources=Join-Path $profile '.ssh\config.d'
foreach($directory in @((Join-Path $profile '.config'),$dataRoot,$root)){
 Assert-SyncPlainPath $directory
 if(-not(Test-Path -LiteralPath $directory)){New-Item -ItemType Directory -Path $directory|Out-Null}
}
[IO.File]::SetAttributes((Join-Path $profile '.config'),([IO.File]::GetAttributes((Join-Path $profile '.config')) -bor [IO.FileAttributes]::Hidden))
$readme=Join-Path $dataRoot 'readme.md';Assert-SyncPlainPath $readme
if(-not(Test-Path -LiteralPath $readme)){Copy-Item -LiteralPath (Join-Path $source 'hosts_readme.md') -Destination $readme}
$rulesPath=Join-Path $dataRoot 'sites.json'
if(-not(Test-Path -LiteralPath $rulesPath)){Copy-Item -LiteralPath (Join-Path $source 'sites.json') -Destination $rulesPath}
$configuration=[IO.File]::ReadAllText($rulesPath)|ConvertFrom-Json
Assert-NetworkSiteConfiguration $configuration
$hostsEnabled=if($configuration.Outputs){[bool]$configuration.Outputs.Hosts}else{$true}
$sshEnabled=if($configuration.Outputs){[bool]$configuration.Outputs.SSH}else{$true}
if($hostsEnabled){Assert-SyncPlainPath $hostSources;if(-not(Test-Path -LiteralPath $hostSources)){New-Item -ItemType Directory -Path $hostSources|Out-Null}}
if($sshEnabled){
 Assert-SyncPlainPath (Join-Path $profile '.ssh')
 Invoke-HostsSyncSshClient -ProfilePath $profile
 Assert-SyncPlainPath $sshSources
}
$encoding=New-Object Text.UTF8Encoding($false)
foreach($site in (@('global')+@($configuration.Sites|ForEach-Object {$_.Id}))){
 $specs=@()
 if($hostsEnabled){$specs+=@{Root=$hostSources;Extension='.hosts';Text="# $site hosts: add IP-address and aliases here. No active mappings supplied.`r`n"}}
 if($sshEnabled){$specs+=@{Root=$sshSources;Extension='.conf';Text="# $site SSH configuration: add explicit Host entries here. No hosts supplied.`r`n"}}
 foreach($spec in $specs){
  $file=Join-Path $spec.Root ($site+$spec.Extension);Assert-SyncPlainPath $file
  if(-not(Test-Path -LiteralPath $file)){[IO.File]::WriteAllText($file,$spec.Text,$encoding)}
 }
}
# The first global Include is sufficient; do not remove existing Host entries.
if($sshEnabled){
$main=Join-Path $profile '.ssh\config';Assert-SyncPlainPath $main
$mainText=[IO.File]::ReadAllText($main)
$firstScoped=[regex]::Match($mainText,'(?im)^\s*(?:Host|Match)\s+')
$include=[regex]::Match($mainText,'(?im)^\s*Include\s+"?active-sites\.conf"?\s*(?:#.*)?$')
if($include.Success -and $firstScoped.Success -and $include.Index -gt $firstScoped.Index){throw 'active-sites.conf 的 Include 位於 Host/Match 區段內，請移至 config 最上方的全域區段。'}
if(-not $include.Success){
 Copy-Item -LiteralPath $main -Destination (Join-Path $root ('ssh-config-before-'+(Get-Date -Format yyyyMMdd-HHmmss)+'.backup'))
 [IO.File]::WriteAllText($main,"Include active-sites.conf`r`n"+$mainText,$encoding)
}
}

# Stop the previous instance before replacing protected runtime scripts.
$existingTask=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if($existingTask){
 Stop-ScheduledTask -TaskName $taskName
 for($i=0;$i -lt 20 -and (Get-ScheduledTask -TaskName $taskName).State -eq 'Running';$i++){Start-Sleep -Milliseconds 500}
 if((Get-ScheduledTask -TaskName $taskName).State -eq 'Running'){throw '無法停止舊同步工作，未覆寫程式。'}
}
function Protect-SyncRuntime {
 param([string]$Path,[switch]$Directory)
 $acl=if($Directory){New-Object Security.AccessControl.DirectorySecurity}else{New-Object Security.AccessControl.FileSecurity}
 $acl.SetAccessRuleProtection($true,$false)
 $admin=New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
 $system=New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
 $user=New-Object Security.Principal.SecurityIdentifier($sid)
 $acl.SetOwner($admin)
 foreach($entry in @(@{SID=$admin;Rights='FullControl'},@{SID=$system;Rights='FullControl'},@{SID=$user;Rights='ReadAndExecute'})){
  if($Directory){$rule=New-Object Security.AccessControl.FileSystemAccessRule($entry.SID,$entry.Rights,'ContainerInherit,ObjectInherit','None','Allow')}
  else{$rule=New-Object Security.AccessControl.FileSystemAccessRule($entry.SID,$entry.Rights,'Allow')}
  $acl.AddAccessRule($rule)
 }
 Set-Acl -LiteralPath $Path -AclObject $acl
}
Protect-SyncRuntime -Path $root -Directory
foreach($name in @('network_sites.ps1','sync_custom_hosts.ps1','watch_custom_hosts.ps1')){
 $destination=Join-Path $root $name;Assert-SyncPlainPath $destination
 Copy-Item -LiteralPath (Join-Path $source $name) -Destination $destination -Force
}
$runtime=[ordered]@{Version=1;OwnerSID=$sid;OwnerName=$identity.Name;ProfilePath=$profile;HostsPath=(Join-Path $WindowsRoot 'System32\drivers\etc\hosts');InstalledAt=(Get-Date).ToString('o')}
[IO.File]::WriteAllText($runtimePath,($runtime|ConvertTo-Json),$encoding)
foreach($file in Get-ChildItem -LiteralPath $root -File -Force){Assert-SyncPlainPath $file.FullName;Protect-SyncRuntime -Path $file.FullName}
foreach($name in @('last-error.json','watcher-fatal-error.json')){if(Test-Path (Join-Path $root $name)){Remove-Item -LiteralPath (Join-Path $root $name) -Force}}
Write-Host '先執行一次 hosts / SSH 同步，確認規則與來源有效…' -ForegroundColor Cyan
$initial=Invoke-CustomHostsSync -ProfilePath $profile -StatePath $root -TargetHostsPath $runtime.HostsPath
if(-not $initial.Success){throw ('首次同步有輸出未成功；查看 '+(Join-Path $root 'status.json'))}
$action=New-ScheduledTaskAction -Execute (Join-Path $WindowsRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+(Join-Path $root 'watch_custom_hosts.ps1')+'"')
$principal=New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings=New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Trigger (New-ScheduledTaskTrigger -AtStartup) -Force|Out-Null
$watcherStarted=Get-Date
Start-ScheduledTask -TaskName $taskName
$freshStatus=$false
for($i=0;$i -lt 30;$i++){
 try{$latest=[IO.File]::ReadAllText((Join-Path $root 'status.json'))|ConvertFrom-Json;if((Get-ScheduledTask -TaskName $taskName).State -eq 'Running' -and [datetime]$latest.CheckedAt -gt $watcherStarted){$freshStatus=$true;break}}catch{}
 Start-Sleep -Seconds 1
}
if(-not $freshStatus){throw '未取得 SYSTEM 背景程式第一輪新狀態，請查看 CustomHostsSync 狀態及錯誤檔。'}
Test-InstalledHostsSync
Write-Host ('編輯網路規則：'+$rulesPath)
Write-Host ('編輯主機清單：'+$hostSources+'\<站點ID>.hosts')
Write-Host ('編輯 SSH 清單：'+$sshSources+'\<站點ID>.conf')
Write-Host '框架已啟用；來源目前為空白範本，不會憑空產生主機或金鑰。'
}
