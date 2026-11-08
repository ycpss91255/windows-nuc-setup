#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name};$script:count++}
function Reject([scriptblock]$Action,[string]$Expected,[string]$Name){$failure=$null;try{& $Action|Out-Null}catch{$failure=$_};Assert ($null -ne $failure -and $failure.Exception -isnot [Management.Automation.ParameterBindingException] -and $failure.Exception.Message.Contains($Expected)) ($Name+'; actual='+$failure.Exception.Message)}
$library=Join-Path $root 'modules/terminal/terminal_hotkey_library.ps1'
. $library
$temp=Join-Path ([IO.Path]::GetTempPath()) ('terminal_mock_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
$module=Join-Path $root 'modules/terminal';$folder=Join-Path $temp 'local data/TerminalHotkey';$startup=Join-Path $temp 'startup link.lnk';$report=Join-Path $temp 'result.json';$listener=Join-Path $folder 'terminal_hotkey_listener.ps1';$log=Join-Path $folder 'status.log'
function Get-SetupTerminalContext {[pscustomobject]@{Folder=$folder;Startup=$startup;IdentityName='fixture-user';UserSID='fixture-sid';UserHome=(Join-Path $temp 'home');PowerShell='fixture powershell.exe';ReportPath=$report}}
$script:registered=0;$script:started=0;$script:saved=0;$script:taskState='Ready';$script:missingTerminal=$false;$script:processes=@();$script:writeRegistration=$true
function Get-Command {param($Name,$ErrorAction) if($Name -ne 'wt.exe'){throw 'unexpected command lookup'};if(-not $script:missingTerminal){[pscustomobject]@{Source='fixture wt.exe'}}}
$script:link=[pscustomobject]@{TargetPath='';Arguments='';WorkingDirectory='';WindowStyle=0;Hotkey=''};$script:link|Add-Member ScriptMethod Save {$script:saved++;[IO.File]::WriteAllText($startup,'synthetic shortcut')}
function New-SetupTerminalShell {$shell=[pscustomobject]@{};$shell|Add-Member ScriptMethod CreateShortcut {param($Path) if($Path -ne $startup){throw 'wrong startup path'};$script:link};return $shell}
function New-ScheduledTaskAction {param($Execute,$Argument) Assert ($Execute -eq 'fixture powershell.exe' -and $Argument.Contains($listener)) 'terminal task retains dynamic listener path';[pscustomobject]@{Execute=$Execute}}
function New-ScheduledTaskPrincipal {param($UserId,$LogonType,$RunLevel) Assert ($UserId -eq 'fixture-user' -and $LogonType -eq 'Interactive' -and $RunLevel -eq 'Limited') 'terminal task remains current interactive user with Limited rights';[pscustomobject]@{UserId=$UserId}}
function Get-ScheduledTask {param($TaskName,$ErrorAction) if($script:taskState){[pscustomobject]@{State=$script:taskState}}}
function Register-ScheduledTask {param($TaskName,$Action,$Principal,[switch]$Force) Assert ($TaskName -eq 'NUC8-TerminalHotkey-fixture-sid') 'terminal task identity is derived from current SID';$script:registered++}
function Start-ScheduledTask {param($TaskName) $script:started++;if($script:writeRegistration){[IO.File]::WriteAllText($log,'REGISTERED: fixture')}}
function Start-Sleep {param($Seconds,$Milliseconds)}
function Get-CimInstance {param($ClassName,$Filter) $script:processes}
$script:missingTerminal=$true;Reject {Invoke-SetupTerminalHotkey -ModuleRoot $module} '找不到 Windows Terminal' 'missing Terminal fails before deployment';$script:missingTerminal=$false
$script:processes=@([pscustomobject]@{ProcessId=123;SessionId=1;CommandLine='powershell '+$listener},[pscustomobject]@{ProcessId=999;SessionId=0;CommandLine='powershell '+$listener},[pscustomobject]@{ProcessId=456;SessionId=1;CommandLine='unrelated'})
Invoke-SetupTerminalHotkey -ModuleRoot $module
$result=[IO.File]::ReadAllText($report)|ConvertFrom-Json
Assert ($result.Success -and $result.User -eq 'fixture-user' -and $result.ProcessIDs.Count -eq 1 -and $result.ProcessIDs[0] -eq 123 -and $script:registered -eq 1 -and $script:started -eq 1) 'terminal succeeds only with current desktop process shortcut and registration'
foreach($name in @('terminal_hotkey_listener.ps1','terminal_hotkey_library.ps1','native/terminal_hotkey.cs')){Assert ((Get-FileHash (Join-Path $folder $name)).Hash -ceq (Get-FileHash (Join-Path $module $name)).Hash) ('terminal self-contained deployment includes exact '+$name)}
Assert ($script:link.WorkingDirectory -eq (Join-Path $temp 'home') -and $script:link.Hotkey -eq '' -and $script:link.WindowStyle -eq 7) 'terminal shortcut uses dynamic home without legacy shell hotkey'
$script:taskState='Running';Invoke-SetupTerminalHotkey -ModuleRoot $module
Assert ($script:registered -eq 1 -and $script:started -eq 1) 'running terminal listener is not duplicated'
$before=$script:saved;Invoke-SetupTerminalHotkey -ModuleRoot $module -VerifyOnly
Assert ($script:saved -eq $before -and $script:registered -eq 1) 'VerifyOnly does not alter shortcut or tasks'
[IO.File]::WriteAllText($log,'REGISTERED: stale'+[Environment]::NewLine+'MESSAGE LOOP FAILED: 5');Reject {Invoke-SetupTerminalHotkey -ModuleRoot $module -VerifyOnly} '未成功註冊' 'native listener failure cannot pass verification'
$script:ownsMutex=$false;$script:released=0;$script:disposed=0;$script:nativeRuns=0;$script:nativeFailure=$false
function New-SetupTerminalMutex {$m=[pscustomobject]@{};$m|Add-Member ScriptMethod WaitOne {param($Timeout) $script:ownsMutex};$m|Add-Member ScriptMethod ReleaseMutex {$script:released++};$m|Add-Member ScriptMethod Dispose {$script:disposed++};return $m}
function Invoke-SetupTerminalNative {param($ModuleRoot,$Terminal,$LogPath,$UserHome) $script:nativeRuns++;if($script:nativeFailure){throw 'native fixture failure'}}
Invoke-SetupTerminalListener -ModuleRoot $module
Assert ($script:nativeRuns -eq 0 -and $script:released -eq 0 -and $script:disposed -eq 1) 'duplicate listener disposes mutex without releasing another owner'
$script:ownsMutex=$true;Invoke-SetupTerminalListener -ModuleRoot $module
Assert ($script:nativeRuns -eq 1 -and $script:released -eq 1 -and $script:disposed -eq 2) 'listener releases acquired mutex on normal native return'
$script:nativeFailure=$true;Reject {Invoke-SetupTerminalListener -ModuleRoot $module} 'native fixture failure' 'listener preserves native failure'
Assert ($script:released -eq 2 -and $script:disposed -eq 3) 'listener releases acquired mutex after failure'
Write-Host ('ALL PASS: '+$script:count+' terminal original-source assertions; TEMP and mocks only')