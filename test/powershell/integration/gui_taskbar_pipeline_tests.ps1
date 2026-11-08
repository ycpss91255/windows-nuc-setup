#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
. (Join-Path $root 'core/gui_stage_library.ps1')
$files=@(Get-SetupGuiStageFiles Taskbar);$finalFiles=@(Get-SetupGuiStageFiles TaskbarFinalize)
Assert ($files.Count -eq 4 -and ($files -join '|') -ceq ($finalFiles -join '|') -and $files -contains 'modules/taskbar/taskbar_settings_library.ps1') 'Taskbar and finite Finalize pin only fixed controller worker and original leaf'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('gui_taskbar_pipeline_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
$script:sid='S-1-5-21-1-2-3-1001';$script:scopeSid=$script:sid;$script:session=0;$script:desktopSession=4;$script:tasks=@{};$script:values=@{};$script:writes=0;$script:delays=@();$script:nativeInfo=0;$script:registered=@();$script:backups=0
$ps=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'WindowsPowerShell/v1.0/powershell.exe'
function Get-SetupGuiIdentity {[pscustomobject]@{CommonDataRoot=$temp;UserSID=$script:scopeSid;SessionId=$script:session;Computer='fixture';PowerShell=$ps}}
function Assert-SetupGuiAncestors {param($CommonDataRoot) if($CommonDataRoot -ne $temp){throw 'wrong fixture parent'}}
function New-SetupGuiProtectedDirectory {param($Path,$UserSid) if(-not $Path.StartsWith($temp)){throw 'outside TEMP'};[void][IO.Directory]::CreateDirectory($Path)}
function Assert-SetupGuiProtectedPath {param($Path,[switch]$Directory,$UserSid) if(-not $Path.StartsWith($temp) -or -not(Microsoft.PowerShell.Management\Test-Path -LiteralPath $Path)){throw 'outside protected fixture'}}
function Get-CimInstance {param($ClassName,$Filter,$ErrorAction) if($ClassName -ne 'Win32_Process' -or $Filter -ne "Name='explorer.exe'"){throw 'unexpected process query'};[pscustomobject]@{SessionId=$script:desktopSession}}
function Invoke-CimMethod {param($InputObject,$MethodName,$ErrorAction) [pscustomobject]@{ReturnValue=0;Sid=$script:sid}}
function New-ScheduledTaskAction {param($Execute,$Argument) if($Execute -cne $ps){throw 'non-OS PowerShell task executable'};[pscustomobject]@{Argument=$Argument}}
function New-ScheduledTaskPrincipal {param($UserId,$LogonType,$RunLevel) if($UserId -cne $script:sid -or $LogonType -cne 'Interactive' -or $RunLevel -cne 'Highest'){throw 'wrong task principal'};[pscustomobject]@{UserId=$UserId}}
function Get-ScheduledTask {param($TaskName,$ErrorAction) if($script:tasks.ContainsKey($TaskName)){[pscustomobject]@{State='Ready'}}}
function Get-ScheduledTaskInfo {param($TaskName,$ErrorAction) $script:nativeInfo++;[pscustomobject]@{LastTaskResult=0}}
function Register-ScheduledTask {param($TaskName,$Action,$Principal,$ErrorAction) if($script:tasks.ContainsKey($TaskName)){throw 'task overwrite'};$script:tasks[$TaskName]=$Action;$script:registered+=@($TaskName)}
function Unregister-ScheduledTask {param($TaskName,[switch]$Confirm,$ErrorAction) $script:tasks.Remove($TaskName)}
function Start-ScheduledTask {param($TaskName,$ErrorAction)
 if($script:tasks[$TaskName].Argument -notmatch '-File "([^"]+)" -Role (Taskbar|TaskbarFinalize) -RunId ([a-f0-9-]{36})$'){throw 'unexpected worker command'}
 $code=Split-Path (Split-Path $Matches[1] -Parent) -Parent;$role=$Matches[2];$run=$Matches[3];$old=$script:session;$script:session=$script:desktopSession
 try{Invoke-SetupGuiWorker -CodeRoot $code -Role $role -RunId $run|Out-Null}finally{$script:session=$old}
}
function Test-Path {param($Path,$LiteralPath,$PathType) if($Path -like 'HK*'){return $true};Microsoft.PowerShell.Management\Test-Path @PSBoundParameters}
function New-ItemProperty {param($Path,$Name,$Value,$PropertyType,[switch]$Force) if($Path -notlike 'HK*'){throw 'unexpected registry write'};$script:values[$Name]=$Value;$script:writes++}
function Get-ItemProperty {param($Path,$ErrorAction) if($Path -notlike 'HK*'){throw 'unexpected registry read'};[pscustomobject]$script:values}
function Remove-ItemProperty {param($Path,$Name,$ErrorAction) if($Path -ne 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'){throw 'unexpected policy removal'};$script:values.Remove($Name);$script:writes++}
function Export-SetupTaskbarBackup {param($Path) if(-not $Path.StartsWith($temp)){throw 'outside TEMP backup'};$script:backups++}
function Start-Sleep {param($Seconds) $script:delays+=@($Seconds)}
$r=Invoke-SetupGuiRole -PackageRoot $root -Role Taskbar;$apply=$r.RunId;$expectedCommand=$script:values.NUC8FinalizeTaskbar;$task='WindowsSetup-Gui-TaskbarFinalize-'+$apply
Assert ($r.Success -and $r.RequiresNextSignIn -and $script:tasks.Count -eq 1 -and $script:tasks.ContainsKey($task) -and $script:nativeInfo -eq 1) 'Apply waits for actual worker exit zero and registers one deferred same-SID Highest GUID task'
Assert ($expectedCommand.StartsWith(('"'+$ps+'" -NoProfile')) -and $expectedCommand.Contains((Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'schtasks.exe')) -and $expectedCommand.Contains($task) -and $expectedCommand -notmatch '\.ps1|EncodedCommand|NUC8-Setup') 'RunOnce contains only OS-qualified PowerShell and fixed GUID schtasks invocation with no public script'
$before=$script:writes;$r=Invoke-SetupGuiFreshVerification -PackageRoot $root -Role Taskbar
Assert (-not $r.Success -and $r.Status -eq 'PendingSignIn' -and $r.Configured -and $r.BindingMatches -and $script:writes -eq $before) 'fresh verification reads exact Edge Replace XML and current policy/RunOnce while honestly pending'
$script:values.Remove('NUC8FinalizeTaskbar');$script:desktopSession=9
Start-ScheduledTask $task
$paths=Get-SetupGuiRunPaths -CommonDataRoot $temp -Role TaskbarFinalize -RunId $apply;$context=Read-SetupGuiContext -CodeRoot $paths.CodeRoot -CommonDataRoot $temp -Role TaskbarFinalize -RunId $apply
$stage=[pscustomobject]@{CodeRoot=$paths.CodeRoot;DataRoot=$paths.DataRoot;CommonDataRoot=$temp;Context=$context};$done=Read-SetupGuiResult $stage
Assert ($done.Success -and $done.Status -eq 'Finalized' -and $done.SessionId -eq 9 -and $done.OriginalDesktopSession -eq 4 -and -not $script:values.ContainsKey('StartLayoutFile') -and -not $script:tasks.ContainsKey($task) -and $script:delays -contains 45) 'Finalize accepts only original SID unique new desktop session and clears its matching policy and own task after 45 seconds'
$r=Invoke-SetupGuiFreshVerification -PackageRoot $root -Role Taskbar
Assert ($r.Success -and $r.Status -eq 'Confirmed' -and -not $r.RequiresNextSignIn) 'fresh current Taskbar verification confirms completed native cleanup without legacy result authority'
$old=Invoke-SetupGuiRole -PackageRoot $root -Role Taskbar;$oldTask='WindowsSetup-Gui-TaskbarFinalize-'+$old.RunId
$new=Invoke-SetupGuiRole -PackageRoot $root -Role Taskbar;$newTask='WindowsSetup-Gui-TaskbarFinalize-'+$new.RunId;$currentLayout=$script:values.StartLayoutFile;$currentRunOnce=$script:values.NUC8FinalizeTaskbar;$before=$script:writes
Start-ScheduledTask $oldTask
$paths=Get-SetupGuiRunPaths -CommonDataRoot $temp -Role TaskbarFinalize -RunId $old.RunId;$context=Read-SetupGuiContext -CodeRoot $paths.CodeRoot -CommonDataRoot $temp -Role TaskbarFinalize -RunId $old.RunId;$stage=[pscustomobject]@{CodeRoot=$paths.CodeRoot;DataRoot=$paths.DataRoot;CommonDataRoot=$temp;Context=$context};$obsolete=Read-SetupGuiResult $stage
Assert (-not $obsolete.Success -and $obsolete.Status -eq 'Obsolete' -and $script:values.StartLayoutFile -ceq $currentLayout -and $script:values.NUC8FinalizeTaskbar -ceq $currentRunOnce -and $script:writes -eq $before -and $script:tasks.ContainsKey($newTask) -and -not $script:tasks.ContainsKey($oldTask)) 'obsolete finalizer clears only itself and cannot clear new Apply policy RunOnce or task'
foreach($wrong in @('SID','SessionZero','OtherSession')){
 $script:scopeSid=$script:sid;$script:session=9
 switch($wrong){SID{$script:scopeSid='S-1-5-21-1-2-3-1002'} SessionZero{$script:session=0} OtherSession{$script:session=8}}
 $before=$script:writes;$failure='';try{Invoke-SetupGuiWorker -CodeRoot $paths.CodeRoot -Role TaskbarFinalize -RunId $old.RunId|Out-Null}catch{$failure=$_.Exception.Message}
 Assert (-not [string]::IsNullOrWhiteSpace($failure) -and $script:writes -eq $before) ('Finalize rejects wrong future execution scope before any setting: '+$wrong)
}
$script:scopeSid=$script:sid;$script:session=0
Assert (-not(Test-Path -LiteralPath (Join-Path $temp 'NUC8-Setup'))) 'Taskbar never publishes executable or authoritative result under old public root'
$originalSid=$script:sid;$originalValues=$script:values.Clone();$script:sid='S-1-5-21-1-2-3-1002';$script:scopeSid=$script:sid;$script:values=@{}
$other=Invoke-SetupGuiRole -PackageRoot $root -Role Taskbar
$script:sid=$originalSid;$script:scopeSid=$originalSid;$script:values=$originalValues;$failure='';$r=$null
try{$r=Invoke-SetupGuiFreshVerification -PackageRoot $root -Role Taskbar}catch{$failure=$_.Exception.Message}
Assert (-not $failure -and -not $r.Success -and $r.Status -eq 'PendingSignIn' -and $r.TaskbarLayout -ceq $currentLayout) 'another local user cannot replace the original user protected layout pointer'