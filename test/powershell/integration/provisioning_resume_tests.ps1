#Requires -Version 5.1
$ErrorActionPreference='Stop'
. ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\modules\init\provisioning_library.ps1')))
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++}
Assert ([bool](Get-Command Invoke-InitSshContinuation -ErrorAction SilentlyContinue)) 'formal user continuation invokes SSH installation'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('init_resume_'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $temp|Out-Null
$ssh=Join-Path $temp 'ssh.ps1'
[IO.File]::WriteAllText($ssh,'$global:initSshCalls++; if($global:initSshFail){throw "synthetic offline"}')
[IO.File]::WriteAllText((Join-Path $temp 'ssh_firewall.ps1'),'function Get-SetupSSHFirewallStatus { [pscustomobject]@{Passed=$global:initFirewallPass;Detail="synthetic firewall"} }')
$global:initFirewallPass=$true
$global:initSshCalls=0;$global:initSshFail=$false
function Save-InitProvisioningState {param($State,$StatePath) $script:lastPhase=$State.Phase}
function Get-NetIPAddress {param($AddressFamily,$ErrorAction) @()}
function Get-CimInstance {param($ClassName,$Filter,$ErrorAction) [pscustomobject]@{State='Running';StartMode='Auto'}}
$state=New-InitProvisioningState 'fixture-machine' 'TEST' 'Z:\removed_usb' ('c'*64)
$state.TargetUserName='fixture';$state.TargetSid='S-1-5-21-1-2-3-1001';$state.Phase='AwaitingLogon'
$context=@{MachineGuid='fixture-machine';Sid=$state.TargetSid;ProfilePath=(Join-Path $temp 'profile');RegisteredProfile=(Join-Path $temp 'profile');ImageState='IMAGE_STATE_COMPLETE';DesktopOwned=$true;IsAdministrator=$true}
foreach($field in @('MachineGuid','Sid','RegisteredProfile','ImageState','DesktopOwned','IsAdministrator')){
 $bad=$context.Clone();$bad[$field]=if($field -in @('DesktopOwned','IsAdministrator')){$false}else{'mismatch'}
 $rejected=$false;try{Invoke-InitSshContinuation -State $state -StatePath 'unused' -Context $bad -SshScriptPath $ssh}catch{$rejected=$true}
 Assert ($rejected -and $global:initSshCalls -eq 0) ('reject before SSH: '+$field)
}
$global:initSshFail=$true
$rejected=$false;try{Invoke-InitSshContinuation $state 'unused' $context $ssh}catch{$rejected=$true}
Assert ($rejected -and $state.Phase -eq 'SshPending' -and $script:lastPhase -eq 'SshPending') 'offline module failure persists retryable pending'
$global:initSshFail=$false
Invoke-InitSshContinuation $state 'unused' $context $ssh
Assert ($global:initSshCalls -eq 2 -and $state.Phase -eq 'Complete') 'retry invokes module again and completes only after Running Auto service'
Assert ($state.SourceRoot -eq 'Z:\removed_usb') 'continuation does not read original USB source'
$global:initFirewallPass=$false
$rejected=$false;try{Invoke-InitSshContinuation $state 'unused' $context $ssh}catch{$rejected=$true}
Assert ($rejected -and $state.Phase -eq 'SshPending') 'Running Auto with failed firewall cannot report Complete'
Assert ([bool](Get-Command Get-InitConnectionInfo -ErrorAction SilentlyContinue)) 'SSH completion supplies dynamic Chinese connection information'
function Get-NetIPAddress {param($AddressFamily,$ErrorAction) @([pscustomobject]@{IPAddress='192.0.2.20';AddressState='Preferred'},[pscustomobject]@{IPAddress='127.0.0.1';AddressState='Preferred'})}
$info=@(Get-InitConnectionInfo -UserName 'fixture-user' -ComputerName 'TEST-PC') -join "`n"
Assert ($info.Contains('TEST-PC') -and $info.Contains('fixture-user') -and $info.Contains('ssh "fixture-user@192.0.2.20"') -and -not $info.Contains('127.0.0.1')) 'connection display includes account host and usable IPv4 command'
Remove-Variable initSshCalls,initSshFail,initFirewallPass -Scope Global
Write-Host ('ALL PASS: '+$script:count+' safe continuation assertions')
