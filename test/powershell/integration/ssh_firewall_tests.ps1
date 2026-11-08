#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
$helper=Join-Path $root 'modules/ssh/ssh_firewall.ps1';if(Test-Path $helper){. $helper}
function Get-NetFirewallRule {param($Name);if(-not $script:missing){$script:rule}}
function Get-NetFirewallAddressFilter {param([Parameter(ValueFromPipeline=$true)]$InputObject);process{[pscustomobject]@{RemoteAddress=$script:addresses}}}
function Get-NetFirewallPortFilter {param([Parameter(ValueFromPipeline=$true)]$InputObject);process{[pscustomobject]@{Protocol=$script:protocol;LocalPort=$script:ports}}}
function Add-Check {param($Name,$Passed,$Detail);$script:verified=[bool]$Passed}
$source=[IO.File]::ReadAllText((Join-Path $root 'core/verification_library.ps1'))
$begin=$source.IndexOf('$scope=@(Get-NetFirewallRule')
if($begin -lt 0){$begin=$source.IndexOf('$sshFirewall=Get-SetupSSHFirewallStatus')}
$end=$source.IndexOf("foreach(`$setting",$begin)
$verify=$source.Substring($begin,$end-$begin)
foreach($kind in @('disabled','outbound','blocked','udp','wrong_port','extra_port','broad_scope','limited_profile','missing','valid','numeric_tcp')){
 $script:rule=[pscustomobject]@{Enabled='True';Direction='Inbound';Action='Allow';Profile='Any'};$script:addresses=@('LocalSubnet');$script:protocol='TCP';$script:ports=@('22');$script:missing=$false
 switch($kind){
  disabled{$script:rule.Enabled='False'}
  outbound{$script:rule.Direction='Outbound'}
  blocked{$script:rule.Action='Block'}
  udp{$script:protocol='UDP'}
  wrong_port{$script:ports=@('2222')}
  extra_port{$script:ports=@('22','80')}
  broad_scope{$script:addresses=@('LocalSubnet','Any')}
  limited_profile{$script:rule.Profile='Private'}
  missing{$script:missing=$true}
  numeric_tcp{$script:protocol='6'}
 }
 $script:verified=$null
 . ([scriptblock]::Create($verify))
 Assert ($script:verified -eq ($kind -in @('valid','numeric_tcp'))) ('actual VerifyOnly SSH firewall contract: '+$kind)
}
# Execute the actual installer firewall branch with fake network commands.
$installer=[IO.File]::ReadAllText((Join-Path $root 'modules/ssh/apply_ssh_settings.ps1'))
$begin=$installer.IndexOf("`$name='OpenSSH-Server-In-TCP'");$end=$installer.IndexOf('if((Get-Service',$begin)
$configure=$installer.Substring($begin,$end-$begin)
function Set-NetFirewallRule {param($Name,$Enabled,$Direction,$Action,$Profile,$RemoteAddress,$Protocol,$LocalPort);$script:updated=$PSBoundParameters;$script:rule=[pscustomobject]@{Enabled=$Enabled;Direction=$Direction;Action=$Action;Profile=$Profile};$script:addresses=@($RemoteAddress);$script:protocol=$Protocol;$script:ports=@($LocalPort)}
function New-NetFirewallRule {param($Name,$DisplayName,$Enabled,$Direction,$Action,$Profile,$RemoteAddress,$Protocol,$LocalPort);$script:updated=$PSBoundParameters;$script:missing=$false;$script:rule=[pscustomobject]@{Enabled=$Enabled;Direction=$Direction;Action=$Action;Profile=$Profile};$script:addresses=@($RemoteAddress);$script:protocol=$Protocol;$script:ports=@($LocalPort)}
foreach($exists in @($true,$false)){
 $script:missing=-not $exists;$script:rule=[pscustomobject]@{Enabled='False';Direction='Outbound';Action='Block'};$script:protocol='UDP';$script:ports=@('80');$script:addresses=@('Any');$script:updated=$null
 . ([scriptblock]::Create($configure))
 Assert ($script:updated.Protocol -eq 'TCP' -and $script:updated.LocalPort -eq '22' -and $script:updated.RemoteAddress -eq 'LocalSubnet') ('installer converges existing or new rule including protocol and port: '+$exists)
}