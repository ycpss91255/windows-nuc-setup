#Requires -Version 5.1
$ErrorActionPreference='Stop'
# Preload before shadows: module autoload must never replace isolated task boundaries.
$script:moduleInitiallyLoaded=[bool](Get-Module ScheduledTasks)
Import-Module ScheduledTasks -ErrorAction Stop
$script:nativeForbiddenCalls=0
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/ssh/mdns_publisher_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$realPaths=(Get-Command Get-SetupMdnsPaths).ScriptBlock
$failed=$false;try{Get-SetupMdnsPaths '../escape'|Out-Null}catch{$failed=$true};Assert $failed 'startup worker RunId不接受任意路徑'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('mdns_startup_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
$script:task=$null;$script:starts=0;$script:stops=0;$script:registers=0;$script:processPresent=$true;$script:ownerSid='S-1-5-18';$script:protected=@{}
$script:facts=[pscustomobject]@{ComputerName='FIXTURE-PC';Addresses=@([pscustomobject]@{InterfaceIndex=7;IPAddress='192.0.2.9'});PolicyAllowed=$true;DnsClientRunning=$true;SshdRunning=$true;DnsClientProcessId=42}
function Get-SetupMdnsPaths {param($RunId) $p=& $realPaths $RunId;$p.Common=$temp;$p.Root=Join-Path $temp 'windows_setup_mdns';$p.Runs=Join-Path $p.Root 'runs';$p.Current=Join-Path $p.Root 'current.json';if($RunId){$p.RunRoot=Join-Path $p.Runs $RunId;$p.CodeRoot=Join-Path $p.RunRoot 'code';$p.Context=Join-Path $p.RunRoot 'context.json';$p.Status=Join-Path $p.RunRoot 'status.json'};return $p}
function Get-SetupMdnsMachineGuid {return '11111111-2222-3333-4444-555555555555'}
function Assert-SetupUpdateAncestors {param($CommonDataRoot) if($CommonDataRoot -cne $temp){throw 'outside fixture common data'}}
function New-SetupUpdateProtectedDirectory {param($Path) if(-not $Path.StartsWith($temp+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'outside fixture protection'};[void][IO.Directory]::CreateDirectory($Path);$script:protected[$Path]=$true}
function Assert-SetupUpdateProtectedPath {param($Path,[switch]$Directory) if(-not $Path.StartsWith($temp+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'outside fixture protected root'};$item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop;if([bool]$item.PSIsContainer -ne [bool]$Directory -or $item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'fixture invalid protected path'};if($Directory -and -not $script:protected.ContainsKey($Path)){throw 'directory lacks fixture protected descriptor'}}
function Get-SetupMdnsPublisherFacts {return $script:facts}
function Get-ScheduledTask {param($TaskName,$TaskPath,$ErrorAction) if($TaskName -ne 'WindowsSetup-mDNS-Publisher' -or $TaskPath -cne '\'){throw 'unapproved task query'};if($script:task){return $script:task}}
function Register-ScheduledTask {param($TaskName,$TaskPath,$Description,$Action,$Principal,$Settings,$Trigger,[switch]$Force,$ErrorAction) if($script:task -and -not $Force){throw 'cannot overwrite existing task'};$script:registers++;$script:task=[pscustomobject]@{TaskName=$TaskName;TaskPath=$TaskPath;Description=$Description;Actions=@($Action);Principal=$Principal;Settings=$Settings;Triggers=@($Trigger);State='Ready'}}
function Unregister-ScheduledTask {$script:nativeForbiddenCalls++;throw 'Native task deletion forbidden'} 
function Stop-ScheduledTask {param($TaskName,$TaskPath,$ErrorAction) $script:stops++;$script:task.State='Ready'}
function Start-ScheduledTask {
 param($TaskName,$TaskPath,$ErrorAction)
 $script:starts++;$script:task.State='Running';$ctx=Read-SetupMdnsCurrent;$paths=Get-SetupMdnsPaths $ctx.RunId;$plans=@(Get-SetupMdnsPublicationPlan -ComputerName $script:facts.ComputerName -Addresses $script:facts.Addresses)
 $value=[ordered]@{Schema=1;RunId=$ctx.RunId;MachineGuid=$ctx.MachineGuid;SourceFingerprint=$ctx.SourceFingerprint;ComputerName=$script:facts.ComputerName;ProcessId=731;DnsClientProcessId=$script:facts.DnsClientProcessId;PlanFingerprint=(Get-SetupMdnsFingerprint $plans $script:facts.DnsClientProcessId);Plans=$plans;Status='Registered';Registered=$true;LeaseCount=$plans.Count;Error='';CheckedAt=[datetime]::UtcNow.ToString('o');RemoteVerified=$false}
 Write-SetupMdnsAtomicJson -Path $paths.Status -Value $value
}
function Get-CimInstance {param($ClassName,$Filter,$ErrorAction) if($ClassName -cne 'Win32_Process' -or $Filter -cne 'ProcessId=731'){throw 'unexpected native process query'};if($script:processPresent){$ctx=Read-SetupMdnsCurrent;$paths=Get-SetupMdnsPaths $ctx.RunId;[pscustomobject]@{SessionId=0;ExecutablePath=$paths.PowerShell;CommandLine=('"'+$paths.PowerShell+'" '+(Get-SetupMdnsTaskArguments $ctx.RunId));CreationDate=[datetime]::UtcNow.AddMinutes(-1)}}}
function Invoke-CimMethod {param($InputObject,$MethodName,$ErrorAction) if($MethodName -cne 'GetOwnerSid'){throw 'unexpected native owner query'};[pscustomobject]@{ReturnValue=0;Sid=$script:ownerSid}}
function Start-Sleep {param($Seconds,$Milliseconds) throw 'positive fixture must be immediately ready, not timeout'}
foreach($name in @('Register-ScheduledTask','Start-ScheduledTask','Stop-ScheduledTask','Get-ScheduledTask','Unregister-ScheduledTask')){if((Get-Command $name).CommandType -ne 'Function' -or (Get-Command $name).ModuleName){throw 'Unsafe native task boundary escaped fixture: '+$name}}
# The real Task constructors only allocate CIM descriptions; registration/start/stop are isolated above.
$r=Invoke-SetupMdnsPublisher -SourceRoot $root
Assert ($r.Success -and $r.Status -ceq 'Registered' -and -not $r.RemoteVerified -and $script:registers -eq 1 -and $script:starts -eq 1) '真控制器建立保護snapshot及原生SYSTEM startup描述後等待新心跳'
$ctx=Read-SetupMdnsCurrent;$paths=Get-SetupMdnsPaths $ctx.RunId
Assert ($ctx.Files.Count -eq 4 -and @($ctx.Files|Where-Object {$_.SHA256 -cnotmatch '^[A-F0-9]{64}$'}).Count -eq 0) 'USB可移除後仍自包含四個已核來源，不記固定user或原磁碟路徑'
$before=@(Get-ChildItem -LiteralPath (Get-SetupMdnsPaths).Root -Recurse -File|ForEach-Object {(Get-FileHash -LiteralPath $_.FullName).Hash}) -join '|'
$r=Invoke-SetupMdnsPublisher -SourceRoot $root -VerifyOnly
$after=@(Get-ChildItem -LiteralPath (Get-SetupMdnsPaths).Root -Recurse -File|ForEach-Object {(Get-FileHash -LiteralPath $_.FullName).Hash}) -join '|'
Assert ($r.Success -and $before -ceq $after -and $script:registers -eq 1 -and $script:stops -eq 0) 'VerifyOnly只觀測既有publisher，不寫檔不重新Register或更改Task'
$r=Invoke-SetupMdnsPublisher -SourceRoot $root
Assert ($r.Success -and $script:registers -eq 1 -and $script:stops -eq 0) '相同程式與正確公告心跳的Apply冪等，不打斷服務'
$original=Get-Content -LiteralPath $paths.Status -Raw -Encoding UTF8
foreach($case in @('wrong_plans','wrong_working_directory','stale','wrong_name','wrong_dns_pid','not_registered','bad_remote_claim','missing_process','wrong_process_owner','wrong_task_action')){
 $status=$original|ConvertFrom-Json;$oldArg=$script:task.Actions[0].Arguments;$oldDirectory=$script:task.Actions[0].WorkingDirectory
 switch($case){wrong_plans{$status.Plans[0].Port=2222} wrong_working_directory{$script:task.Actions[0].WorkingDirectory='C:\unsafe'} stale{$status.CheckedAt=[datetime]::UtcNow.AddMinutes(-2).ToString('o')} wrong_name{$status.ComputerName='OTHER-PC'} wrong_dns_pid{$status.DnsClientProcessId=99} not_registered{$status.Registered=$false} bad_remote_claim{$status.RemoteVerified=$true} missing_process{$script:processPresent=$false} wrong_process_owner{$script:ownerSid='S-1-5-21-1-2-3-1001'} wrong_task_action{$script:task.Actions[0].Arguments+=' -Command unsafe'}}
 Write-SetupMdnsAtomicJson $paths.Status $status;$ready=$false
 try{$ready=(Invoke-SetupMdnsPublisher -SourceRoot $root -VerifyOnly).Success}catch{}
 Assert (-not $ready -and $script:registers -eq 1 -and $script:stops -eq 0) ('錯誤或未知來源不得因本機解析或Task存在假PASS '+$case)
 $script:task.Actions[0].Arguments=$oldArg;$script:task.Actions[0].WorkingDirectory=$oldDirectory;$script:processPresent=$true;$script:ownerSid='S-1-5-18'
}
[IO.File]::WriteAllText($paths.Status,$original,[Text.UTF8Encoding]::new($true))
$foreign=$script:task;$script:task.Principal.UserId='S-1-5-21-1-2-3-1001';$failed=$false
try{Invoke-SetupMdnsPublisher -SourceRoot $root|Out-Null}catch{$failed=$true}
Assert ($failed -and $script:stops -eq 0 -and $script:registers -eq 1) '既有同名foreign principal不接管不停止不Force覆寫'
$script:task.Principal.UserId='SYSTEM'
$copied=Join-Path $paths.CodeRoot 'modules/ssh/native/mdns_publisher.cs';[IO.File]::AppendAllText($copied,'//tampered');$failed=$false
try{Invoke-SetupMdnsPublisher -SourceRoot $root -VerifyOnly|Out-Null}catch{$failed=$true};Assert $failed 'snapshot來源變動即拒絕，而非只信心跳檔'
Copy-Item -LiteralPath (Join-Path $root 'modules/ssh/native/mdns_publisher.cs') -Destination $copied
$package=Join-Path $temp 'new_package'
foreach($name in Get-SetupMdnsSourceNames){$target=Join-Path $package $name;[void][IO.Directory]::CreateDirectory((Split-Path $target -Parent));Copy-Item -LiteralPath (Join-Path $root $name) -Destination $target}
[IO.File]::AppendAllText((Join-Path $package 'modules/ssh/native/mdns_publisher.cs'),'//new source revision')
$r=Invoke-SetupMdnsPublisher -SourceRoot $package
Assert ($r.Success -and $script:stops -eq 1 -and $script:registers -eq 2 -and $script:starts -eq 2 -and $r.RunId -cne $ctx.RunId) '程式更新只停止已確認owner後換新snapshot與新註冊心跳'
Assert ($script:nativeForbiddenCalls -eq 0) 'startup隔離OS mutation forbidden spy為0，模組預載後所有Task邊界仍fixture'
