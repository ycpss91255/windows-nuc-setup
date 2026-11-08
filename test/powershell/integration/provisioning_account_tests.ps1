#Requires -Version 5.1
$ErrorActionPreference='Stop'
. ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\modules\init\provisioning_library.ps1')))
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++}
Assert ([bool](Get-Command New-InitProvisioningAccount -ErrorAction SilentlyContinue)) 'safe callable account orchestration exists'
$script:events=New-Object Collections.Generic.List[string]
$script:user=$null;$script:member=$false;$script:failGroup=$false
function Save-InitProvisioningState {param($State,$StatePath) $script:events.Add('save:'+$State.Phase);$script:saved=$State|ConvertTo-Json}
function Get-LocalUser {param($Name,$SID,$ErrorAction) if($script:user){return $script:user}}
function New-LocalUser {param($Name,$Password,$ErrorAction) Assert ($Password -is [Security.SecureString]) 'native account creation receives SecureString';$script:events.Add('create');$script:user=[pscustomobject]@{Name=$Name;SID=[pscustomobject]@{Value='S-1-5-21-1-2-3-1001'};Enabled=$true};return $script:user}
function Add-LocalGroupMember {param($SID,$Member,$ErrorAction) Assert ($SID -eq 'S-1-5-32-544') 'administrators group identified by SID';$script:events.Add('group');if($script:failGroup){throw 'synthetic group failure'};$script:member=$true}
function Get-LocalGroupMember {param($SID,$ErrorAction) if($script:member){return $script:user}}
$secure=ConvertTo-SecureString 'fixture-secret' -AsPlainText -Force
$state=New-InitProvisioningState 'fixture' 'TEST' 'R:\copy' ('a'*64)
New-InitProvisioningAccount -State $state -UserName 'new-user' -Password $secure -StatePath 'unused'
Assert ($state.Phase -eq 'AccountReady' -and $state.TargetSid -eq 'S-1-5-21-1-2-3-1001') 'verified enabled administrator reaches AccountReady'
Assert ($script:events[0] -eq 'save:Prepared' -and $script:events.IndexOf('save:AccountCreated') -lt $script:events.IndexOf('group')) 'persist account ownership before group mutation'
Assert ($script:saved -notmatch 'fixture-secret|Password') 'saved state excludes password'
$before=$script:events.Count
$other=New-InitProvisioningState 'fixture' 'TEST' 'R:\copy' ('a'*64)
$rejected=$false;try{New-InitProvisioningAccount $other 'new-user' $secure 'unused'}catch{$rejected=$true}
Assert ($rejected -and $script:events.Count -eq $before) 'existing same-name account is never reset or elevated'
$script:user=$null;$script:member=$false;$script:failGroup=$true
$retry=New-InitProvisioningState 'fixture' 'TEST' 'R:\copy' ('a'*64)
$rejected=$false;try{New-InitProvisioningAccount $retry 'retry-user' $secure 'unused'}catch{$rejected=$true}
Assert ($rejected -and $retry.Phase -eq 'AccountCreated' -and $script:user.Name -eq 'retry-user') 'group failure retains account and owned SID for recovery'
$script:failGroup=$false
$creates=@($script:events|Where-Object {$_ -eq 'create'}).Count
New-InitProvisioningAccount $retry 'retry-user' $null 'unused'
Assert ($retry.Phase -eq 'AccountReady' -and @($script:events|Where-Object {$_ -eq 'create'}).Count -eq $creates) 'recovery uses owned SID without recreating account or asking password'
$script:user.Enabled=$false
$rejected=$false;try{New-InitProvisioningAccount $retry 'retry-user' $null 'unused'}catch{$rejected=$true}
Assert $rejected 'disabled owned account is not silently enabled'
$secure.Dispose()
Write-Host ('ALL PASS: '+$script:count+' safe mocked account assertions')
