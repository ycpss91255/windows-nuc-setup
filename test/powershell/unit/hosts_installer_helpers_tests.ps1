#Requires -Version 5.1
$ErrorActionPreference='Stop'
$package=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
function Reject([scriptblock]$Action,[string]$Name){$caught=$false;try{& $Action|Out-Null}catch{$caught=$true};Assert $caught $Name}
$library=Join-Path $package 'modules/ssh/hosts_sync_library.ps1'
Assert (Test-Path $library) 'hosts安裝器提供可安全載入的具名原始函式'
. $library
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('hosts_installer_'+[guid]::NewGuid().ToString('N'))
$profile=Join-Path $fixture 'profile';$runtime=Join-Path $fixture 'runtime';$windows=Join-Path $fixture 'windows'
[void][IO.Directory]::CreateDirectory($profile)
[void][IO.Directory]::CreateDirectory((Join-Path $windows 'System32/drivers/etc'))
[IO.File]::WriteAllText((Join-Path $windows 'System32/drivers/etc/hosts'),'127.0.0.1 localhost')
$identity=[pscustomobject]@{User=[pscustomobject]@{Value='S-1-5-21-123-456-789-1001'};Name='fixture'}
$call=@{RuntimeRoot=$runtime;ProfilePath=$profile;UserIdentity=$identity;WindowsRoot=$windows}
$script:taskState='';$script:stuck=$false;$script:registered=0;$script:started=0;$script:aclWrites=0
function Get-ItemProperty {param($Path) [pscustomobject]@{ProfileImagePath=$profile}}
function Get-ScheduledTask {param($TaskName,$ErrorAction) if($script:taskState){[pscustomobject]@{State=$script:taskState}}}
function Stop-ScheduledTask {param($TaskName) if(-not $script:stuck){$script:taskState='Ready'}}
function Start-ScheduledTask {param($TaskName) $script:started++;$script:taskState='Running';$p=Join-Path $runtime 'status.json';if(Test-Path $p){$j=Get-Content $p -Raw|ConvertFrom-Json;$j.CheckedAt=(Get-Date).AddSeconds(1).ToString('o');$j|ConvertTo-Json -Depth 10|Set-Content $p -Encoding UTF8}}
function New-ScheduledTaskAction {param($Execute,$Argument) [pscustomobject]@{Execute=$Execute;Argument=$Argument}}
function New-ScheduledTaskPrincipal {param($UserId,$LogonType,$RunLevel) [pscustomobject]@{UserId=$UserId}}
function New-ScheduledTaskSettingsSet {param($ExecutionTimeLimit,$MultipleInstances,$RestartCount,$RestartInterval,[switch]$StartWhenAvailable,[switch]$AllowStartIfOnBatteries,[switch]$DontStopIfGoingOnBatteries) @{}}
function New-ScheduledTaskTrigger {param([switch]$AtStartup) @{}}
function Register-ScheduledTask {param($TaskName,$Action,$Principal,$Settings,$Trigger,[switch]$Force) $script:registered++}
function Set-Acl {param($LiteralPath,$AclObject,$Path) $script:aclWrites++}
function Start-Sleep {param($Seconds,$Milliseconds)}
function Get-NetworkSnapshot {[pscustomobject]@{Adapters=@();Warnings=@()}}
function Invoke-HostsSyncSshClient {param($ProfilePath) [void][IO.Directory]::CreateDirectory((Join-Path $ProfilePath '.ssh/config.d'));$p=Join-Path $ProfilePath '.ssh/config';if(-not(Test-Path $p)){[IO.File]::WriteAllText($p,'# personal configuration')}}
Reject {Invoke-SetupHostsSync @call -VerifyOnly} '未安裝驗證拒絕'
Reject {Invoke-SetupHostsSync @call -SyncOnly} '未安裝單次同步拒絕'
Reject {Invoke-SetupHostsSync @call -Mode Hosts} '安裝不接受局部Mode'
Invoke-SetupHostsSync @call|Out-Null
Assert ($script:registered -eq 1 -and $script:started -eq 1 -and $script:aclWrites -gt 0) '安裝實際編排排程與ACL邊界'
Assert ((Get-Content (Join-Path $runtime 'runtime.json') -Raw|ConvertFrom-Json).OwnerSID -eq $identity.User.Value) 'runtime保留動態owner'
Assert ([IO.File]::ReadAllText((Join-Path $profile '.ssh/config')).StartsWith('Include active-sites.conf')) '首次安裝在全域加入Include'
Assert (Test-Path (Join-Path $profile '.config/hosts/hosts.d/global.hosts')) '建立空白hosts來源'
Assert (Test-Path (Join-Path $profile '.ssh/config.d/global.conf')) '建立空白SSH來源'
Invoke-SetupHostsSync @call -VerifyOnly|Out-Null
Invoke-SetupHostsSync @call -SyncOnly -Mode Hosts|Out-Null
Assert ($script:started -eq 2) '單次同步後恢復背景工作'
Invoke-SetupHostsSync @call|Out-Null
Assert ($script:registered -eq 2) '同owner可重跑安裝'
$runtimePath=Join-Path $runtime 'runtime.json';$saved=[IO.File]::ReadAllText($runtimePath)
$j=$saved|ConvertFrom-Json;$j.OwnerSID='S-1-5-18';$j|ConvertTo-Json|Set-Content $runtimePath -Encoding UTF8
Reject {Invoke-SetupHostsSync @call} '拒絕其他owner接管'
[IO.File]::WriteAllText($runtimePath,$saved)
$script:taskState='Ready';Reject {Invoke-SetupHostsSync @call -VerifyOnly} '停止背景工作拒絕驗證';$script:taskState='Running'
$script:stuck=$true;Reject {Invoke-SetupHostsSync @call -SyncOnly} '無法停止時拒絕同步';Reject {Invoke-SetupHostsSync @call} '無法停止時拒絕覆寫runtime';$script:stuck=$false
$fatal=Join-Path $runtime 'watcher-fatal-error.json';[IO.File]::WriteAllText($fatal,'{}');Reject {Invoke-SetupHostsSync @call -VerifyOnly} '背景啟動錯誤拒絕驗證';Remove-Item -LiteralPath $fatal
$statusPath=Join-Path $runtime 'status.json';$savedStatus=[IO.File]::ReadAllText($statusPath);$j=$savedStatus|ConvertFrom-Json;$j.Outputs.Hosts.CheckedAt=(Get-Date).AddHours(-1).ToString('o');$j|ConvertTo-Json -Depth 10|Set-Content $statusPath -Encoding UTF8
Reject {Invoke-SetupHostsSync @call -VerifyOnly -Mode Hosts} '過期輸出狀態拒絕驗證'
[IO.File]::WriteAllText($statusPath,$savedStatus)
$hosts=Join-Path $windows 'System32/drivers/etc/hosts';$savedHosts=[IO.File]::ReadAllText($hosts);[IO.File]::AppendAllText($hosts,'changed')
Reject {Invoke-SetupHostsSync @call -VerifyOnly -Mode Hosts} '輸出hash變更拒絕驗證';[IO.File]::WriteAllText($hosts,$savedHosts)
$global=Join-Path $profile '.config/hosts/hosts.d/global.hosts';[IO.File]::AppendAllText($global,'# changed')
Reject {Invoke-SetupHostsSync @call -VerifyOnly -Mode Hosts} '來源digest變更拒絕驗證'
function Get-ItemProperty {param($Path) [pscustomobject]@{ProfileImagePath=(Join-Path $fixture 'other')}}
Reject {Invoke-SetupHostsSync @call} 'SID對應profile不一致拒絕'
Write-Host 'ALL PASS: hosts installer named-source boundary tests'
