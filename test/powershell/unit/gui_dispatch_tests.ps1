#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name};$script:count++}
function Reject([scriptblock]$Action,[string]$Expected,[string]$Name){$failure=$null;try{& $Action|Out-Null}catch{$failure=$_};Assert ($null -ne $failure -and $failure.Exception -isnot [Management.Automation.ParameterBindingException] -and $failure.Exception.Message.Contains($Expected)) ($Name+'; actual='+$failure.Exception.Message)}
. (Join-Path $root 'core/gui_stage_library.ps1')
$scope=Get-SetupGuiIdentity
Assert ($scope.UserSID -and $scope.Computer -ceq $env:COMPUTERNAME -and $scope.SessionId -ge 0) 'GUI identity reads actual current scope without applying any setting'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('gui_dispatch_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
$script:scope=[pscustomobject]@{UserSID='S-1-5-21-1-2-3-1001';Computer='fixture';SessionId=0;CommonDataRoot=$temp;PowerShell='fixture powershell.exe'}
function Get-SetupGuiIdentity {$script:scope}
$script:processes=@([pscustomobject]@{SessionId=4;Owner='S-1-5-21-1-2-3-1001'},[pscustomobject]@{SessionId=4;Owner='S-1-5-21-1-2-3-1001'},[pscustomobject]@{SessionId=7;Owner='S-1-5-21-1-2-3-2001'})
function Get-CimInstance {param($ClassName,$Filter) Assert ($ClassName -eq 'Win32_Process' -and $Filter -eq "Name='explorer.exe'") 'desktop discovery only queries Explorer processes';$script:processes}
function Invoke-CimMethod {param($InputObject,$MethodName) [pscustomobject]@{Sid=$InputObject.Owner;ReturnValue=0}}
Assert ((Get-SetupGuiDesktopSession $script:scope) -eq 4) 'duplicate Explorer processes in same user session resolve to one desktop'
$script:processes+=@([pscustomobject]@{SessionId=5;Owner=$script:scope.UserSID});Reject {Get-SetupGuiDesktopSession $script:scope} '唯一' 'ambiguous sessions cannot silently select a desktop'
$script:processes=@();Reject {Get-SetupGuiDesktopSession $script:scope} '唯一' 'missing same-user desktop cannot start UI worker'
$script:processes=@([pscustomobject]@{SessionId=4;Owner=$script:scope.UserSID})
$script:created=0;$script:disposed=0;$script:started=0;$script:removed=0;$script:taskState='Ready';$script:writeReport=$true;$script:localRuns=0;$script:failedResult=$false;$script:stages=@();$script:clock=[datetime]'2020-01-01'
function Get-Date {$script:clock=$script:clock.AddSeconds(31);$script:clock}
function New-SetupGuiStage {param($SourceRoot,$CommonDataRoot,$Role,$UserSid,$CallerSession,$DesktopSession,$Computer,[switch]$VerifyOnly)
 $script:created++;Assert ($SourceRoot -eq $root -and $UserSid -eq $script:scope.UserSID -and $CallerSession -eq $script:scope.SessionId -and $DesktopSession -eq 4) 'controller stages exact current caller and selected desktop'
 $paths=Get-SetupGuiRunPaths -CommonDataRoot $CommonDataRoot -Role $Role -RunId ([guid]::NewGuid().ToString('D'));[void][IO.Directory]::CreateDirectory((Join-Path $paths.CodeRoot 'core'));[void][IO.Directory]::CreateDirectory($paths.DataRoot)
 [IO.File]::WriteAllText((Join-Path $paths.CodeRoot 'core/gui_worker.ps1'),'inert')
 $lock=[pscustomobject]@{};$lock|Add-Member ScriptMethod Dispose {$script:disposed++}
 $script:stage=[pscustomobject]@{CodeRoot=$paths.CodeRoot;DataRoot=$paths.DataRoot;CommonDataRoot=$CommonDataRoot;Lock=$lock;Context=[pscustomobject]@{Schema=1;Role=$Role;RunId=(Split-Path $paths.RunRoot -Leaf);CallerSID=$UserSid;UserSID=$UserSid;CallerSession=$CallerSession;DesktopSession=$DesktopSession;Computer=$Computer;VerifyOnly=[bool]$VerifyOnly}}
 $script:stages+=@($script:stage);return $script:stage
}
function Read-SetupGuiContext {param($CodeRoot,$CommonDataRoot,$Role,$RunId) if($CodeRoot -ne $script:stage.CodeRoot -or $RunId -cne $script:stage.Context.RunId){throw 'wrong context lookup'};$script:stage.Context}
function Assert-SetupGuiProtectedPath {param($Path,[switch]$Directory,$UserSid) if(-not $Path.StartsWith($temp)){throw 'outside TEMP'}}
function Read-SetupGuiResult {param($Stage) [pscustomobject]@{Success=(-not $script:failedResult);Error='fixture result failure';RunId=$Stage.Context.RunId}}
function New-ScheduledTaskAction {param($Execute,$Argument) Assert ($Execute -ceq 'fixture powershell.exe' -and $Argument.Contains((Join-Path $script:stage.CodeRoot 'core/gui_worker.ps1')) -and $Argument.Contains($script:stage.Context.RunId) -and $Argument.Contains('-Role Explorer') -and -not $Argument.Contains('EncodedCommand')) 'task launches fixed staged worker with only bounded role and run ID';[pscustomobject]@{Execute=$Execute}}
function New-ScheduledTaskPrincipal {param($UserId,$LogonType,$RunLevel) Assert ($UserId -ceq $script:scope.UserSID -and $LogonType -ceq 'Interactive' -and $RunLevel -ceq 'Highest') 'GUI task binds original SID interactive highest token';[pscustomobject]@{UserId=$UserId}}
function Get-ScheduledTask {param($TaskName,$ErrorAction) if($script:started -gt 0){[pscustomobject]@{State=$script:taskState}}}
function Register-ScheduledTask {param($TaskName,$Action,$Principal,$ErrorAction) Assert ($TaskName.Contains($script:stage.Context.RunId)) 'GUI task uses unique current-run identity'}
function Start-ScheduledTask {param($TaskName) $script:started++;if($script:writeReport){[IO.File]::WriteAllText((Join-Path $script:stage.DataRoot (Get-SetupGuiResultName $script:stage.Context)),'fixture')}}
function Unregister-ScheduledTask {param($TaskName,[switch]$Confirm) $script:removed++}
function Start-Sleep {param($Seconds)}
function Invoke-SetupGuiLocalWorker {param($Stage,$Scope) $script:localRuns++}
Invoke-SetupGuiRole -PackageRoot $root -Role Explorer -VerifyOnly|Out-Null
Assert ($script:started -eq 1 -and $script:removed -eq 1 -and $script:disposed -eq 1 -and $script:stage.Context.VerifyOnly) 'session-zero controller launches bound worker reads result and always disposes stage lock'
$script:started=0;$script:failedResult=$true;Reject {Invoke-SetupGuiRole -PackageRoot $root -Role Explorer} 'fixture result failure' 'false GUI result propagates as module failure';$script:failedResult=$false
Assert ($script:disposed -eq 2) 'failed GUI result releases controller lock'
$before=$script:created;Reject {Invoke-SetupGuiRole -PackageRoot $root -Role Explorer -Worker} 'session 0' 'legacy Worker switch cannot bypass desktop identity in session zero';Assert ($script:created -eq $before) 'rejected session-zero Worker bypass stages nothing'
$script:scope.SessionId=4;Invoke-SetupGuiRole -PackageRoot $root -Role Explorer -Worker|Out-Null
Assert ($script:localRuns -eq 1 -and $script:disposed -eq 3) 'interactive Worker API executes same protected-stage protocol locally'
$script:scope.SessionId=0;$script:started=0;$script:writeReport=$false;$script:taskState='Running'
Reject {Invoke-SetupGuiRole -PackageRoot $root -Role Explorer} '尚未取得' 'worker timeout cannot return stale legacy result'
Assert ($script:disposed -eq 4 -and $script:removed -eq 2) 'timeout releases controller lock but does not unregister still-running task'
Write-Host ('ALL PASS: '+$script:count+' GUI dispatch assertions; no real tasks or UI changes')