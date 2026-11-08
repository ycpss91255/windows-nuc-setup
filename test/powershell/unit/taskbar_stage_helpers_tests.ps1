#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
. (Join-Path $root 'core/gui_stage_library.ps1')
. (Join-Path $root 'modules/taskbar/taskbar_stage_library.ps1')
. (Join-Path $root 'modules/taskbar/taskbar_settings_library.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('taskbar_stage_leaf_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
$sid='S-1-5-21-1-2-3-1001';$ps=Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'WindowsPowerShell/v1.0/powershell.exe'
$scope=[pscustomobject]@{CommonDataRoot=$temp;UserSID=$sid;SessionId=4;Computer='fixture';PowerShell=$ps}
$script:tasks=@{};$script:registry=@{};$script:badTask='';$script:dropRunOnce=$false;$script:removed=@();$script:delays=@()
function Get-SetupGuiIdentity {$scope}
function Assert-SetupGuiAncestors {param($CommonDataRoot) if($CommonDataRoot -cne $temp){throw 'outside TEMP common root'}}
function New-SetupGuiProtectedDirectory {param($Path,$UserSid) if(-not $Path.StartsWith($temp)){throw 'outside TEMP'};[void][IO.Directory]::CreateDirectory($Path)}
function Assert-SetupGuiProtectedPath {param($Path,[switch]$Directory,$UserSid) if(-not $Path.StartsWith($temp) -or -not(Microsoft.PowerShell.Management\Test-Path -LiteralPath $Path)){throw 'outside TEMP or missing protected fixture'}}
function Test-Path {param($Path,$LiteralPath,$PathType) if($Path -like 'HKCU:*'){return $true};Microsoft.PowerShell.Management\Test-Path @PSBoundParameters}
function New-ScheduledTaskAction {param($Execute,$Argument) if($Execute -cne $ps){throw 'non-OS native executable'};[pscustomobject]@{Execute=$Execute;Arguments=$Argument}}
function New-ScheduledTaskPrincipal {param($UserId,$LogonType,$RunLevel) [pscustomobject]@{UserId=$UserId;LogonType=$LogonType;RunLevel=$RunLevel}}
function Get-ScheduledTask {param($TaskName,$ErrorAction) if($script:tasks.ContainsKey($TaskName)){$script:tasks[$TaskName]}}
function Register-ScheduledTask {param($TaskName,$Action,$Principal,$ErrorAction)
 if($script:badTask -eq 'Missing'){return}
 $a=[pscustomobject]@{Execute=$Action.Execute;Arguments=$Action.Arguments};$p=[pscustomobject]@{UserId=$Principal.UserId;LogonType=$Principal.LogonType;RunLevel=$Principal.RunLevel}
 switch($script:badTask){Action{$a.Arguments='-File other.ps1'} Principal{$p.UserId='S-1-5-21-1-2-3-1002'} RunLevel{$p.RunLevel='Limited'} Logon{$p.LogonType='S4U'}}
 $script:tasks[$TaskName]=[pscustomobject]@{State='Ready';Actions=@($a);Principal=$p}
}
function Unregister-ScheduledTask {param($TaskName,[switch]$Confirm,$ErrorAction) $script:tasks.Remove($TaskName)}
function New-ItemProperty {param($Path,$Name,$Value,$PropertyType,[switch]$Force) if($Path -ne 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -or $Name -ne 'NUC8FinalizeTaskbar' -or $PropertyType -ne 'String' -or -not $Force){throw 'unexpected fixture registry write'};if(-not $script:dropRunOnce){$script:registry[$Name]=$Value}}
function Get-ItemProperty {param($Path,$ErrorAction) if($Path -notlike 'HKCU:*'){throw 'unexpected native read'};[pscustomobject]$script:registry}
function Remove-ItemProperty {param($Path,$Name,$ErrorAction) if($Path -ne 'HKCU:\Software\Policies\Microsoft\Windows\Explorer'){throw 'unexpected removal'};$script:registry.Remove($Name);$script:removed+=@($Name)}
function Start-Sleep {param($Seconds) $script:delays+=@($Seconds)}
function New-FixtureApply([switch]$VerifyOnly){
 $stage=New-SetupGuiStage -SourceRoot $root -CommonDataRoot $temp -Role Taskbar -UserSid $sid -CallerSession 4 -DesktopSession 4 -Computer fixture -VerifyOnly:$VerifyOnly
 [IO.File]::WriteAllText((Join-Path $stage.DataRoot 'TaskbarLayout.xml'),'<Layout><CustomTaskbarLayoutCollection PinListPlacement="Replace"><TaskbarPinList><DesktopApp DesktopApplicationID="MSEdge"/></TaskbarPinList></CustomTaskbarLayoutCollection></Layout>')
 return $stage
}
$stage=New-FixtureApply
try{Register-SetupTaskbarFinalize -Stage $stage -Scope $scope;$binding=Get-SetupTaskbarLayoutBinding -CommonDataRoot $temp -Context $stage.Context;$baseline=$stage.Context.RunId;$baselineLayout=$binding.LayoutPath}finally{$stage.Lock.Dispose()}
Assert ($binding.ApplyRunID -ceq $baseline -and $binding.PendingFinalizeTask -and $script:registry.NUC8FinalizeTaskbar -ceq $binding.FinalizeCommand) 'original stage helper registers protected GUID task RunOnce and matching per-SID pointer'
$script:registry.StartLayoutFile=$baselineLayout;$script:registry.LockedStartLayout=1
$finalContext=[pscustomobject]@{RunId=$baseline;ApplyRunID=$baseline;UserSID=$sid;Computer='fixture'}
$r=Invoke-SetupTaskbarBoundFinalize -CommonDataRoot $temp -Context $finalContext
Assert ($r.Success -and $script:delays -contains 45 -and $script:removed.Count -eq 2) 'original bound helper invokes original matching policy cleanup'
$finalContext.ApplyRunID=[guid]::NewGuid().ToString('D');$before=$script:removed.Count;$r=Invoke-SetupTaskbarBoundFinalize -CommonDataRoot $temp -Context $finalContext
Assert (-not $r.Success -and $r.Status -eq 'Obsolete' -and $script:removed.Count -eq $before) 'original bound helper does not clear a different Apply'
Complete-SetupTaskbarFinalizeTask -RunId $baseline;$binding=Get-SetupTaskbarLayoutBinding -CommonDataRoot $temp -Context $stage.Context
Assert (-not $binding.PendingFinalizeTask) 'original self-cleanup removes only fixed matching task'
function Invoke-SetupGuiWorker {param($CodeRoot,$Role,$RunId) $expected=Get-SetupGuiRunPaths -CommonDataRoot $temp -Role TaskbarFinalize -RunId $baseline;Assert ($Role -ceq 'TaskbarFinalize' -and $RunId -ceq $baseline -and $CodeRoot -ceq $expected.CodeRoot) 'standalone pending helper dispatches only original protected fixed worker'}
Invoke-SetupTaskbarFinalizePending
foreach($failureMode in @('Missing','Action','Principal','RunLevel','Logon','RunOnce')){
 $script:badTask=$(if($failureMode -eq 'RunOnce'){''}else{$failureMode});$script:dropRunOnce=($failureMode -eq 'RunOnce');$stage=New-FixtureApply;$failure=''
 try{Register-SetupTaskbarFinalize -Stage $stage -Scope $scope}catch{$failure=$_.Exception.Message}finally{$stage.Lock.Dispose()}
 Assert ($failure.Contains('工作列收尾')) ('controller must read back coherent native task and RunOnce before success: '+$failureMode)
}