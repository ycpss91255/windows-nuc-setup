#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/init/provisioning_library.ps1')
function Assert([bool]$Passed,[string]$Name){Microsoft.PowerShell.Utility\Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
$fixture=Join-Path $env:TEMP ('checkpoint_native_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture);$fixture=[IO.Path]::GetFullPath($fixture)
$sid='S-1-5-21-1-2-3-1001';$hash='a'*64;$script:aclWrites=0;$script:messages=[Collections.Generic.List[string]]::new();$script:accountReads=0;$script:installed=$true
function Descriptor([bool]$Directory){
 $a=if($Directory){[Security.AccessControl.DirectorySecurity]::new()}else{[Security.AccessControl.FileSecurity]::new()};$a.SetAccessRuleProtection($true,$false);$a.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
 foreach($id in @('S-1-5-18','S-1-5-32-544')){$flags=if($Directory){'ContainerInherit,ObjectInherit'}else{'None'};$a.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($id),'FullControl',$flags,'None','Allow'))};return $a
}
function Get-Acl {param($LiteralPath,$ErrorAction) if(-not ([IO.Path]::GetFullPath($LiteralPath)).StartsWith($fixture,[StringComparison]::OrdinalIgnoreCase)){throw 'ACL outside owned TEMP'};Descriptor ([IO.Directory]::Exists($LiteralPath))}
function Set-Acl {param($LiteralPath,$AclObject,$ErrorAction) if(-not ([IO.Path]::GetFullPath($LiteralPath)).StartsWith($fixture,[StringComparison]::OrdinalIgnoreCase)){throw 'ACL write outside owned TEMP'};$script:aclWrites++}
function Get-LocalUser {param($SID,$ErrorAction) $script:accountReads++;[pscustomobject]@{Name='fixture';SID=[pscustomobject]@{Value=$script:sid};Enabled=$true}}
function Get-LocalGroupMember {param($SID,$ErrorAction) [pscustomobject]@{SID=[pscustomobject]@{Value=$script:sid}}}
function Get-ProvisioningPackage {
 param([switch]$AllInstalledPackages,$PackagePath,$LogsDirectoryPath,$ErrorAction)
 if($PackagePath){return [pscustomobject]@{PackageID='1c2605ea-96ae-42fc-8f11-45fc0cb9d133';PackageName='windows_setup_hide_oobe';Version='1.0';Rank=0;OwnerType=5000;IsInstalled=$false}}
 if($AllInstalledPackages -and $script:installed){[pscustomobject]@{PackageID='1c2605ea-96ae-42fc-8f11-45fc0cb9d133';PackageName='windows_setup_hide_oobe';Version='1.0';IsInstalled=$true}}
}
function New-LocalUser {throw 'checkpoint cannot create or reset an account'}
function Set-LocalUser {throw 'checkpoint cannot reset a password'}
function Add-LocalGroupMember {throw 'checkpoint cannot modify group membership'}
function Install-ProvisioningPackage {throw 'checkpoint cannot reinstall provisioning'}
function Write-Host {param($Object,$ForegroundColor) $script:messages.Add([string]$Object)}
function State([string]$Phase,[string]$Hash=$hash){$s=New-InitProvisioningState 'fixture-machine' 'FIXTURE' 'old USB removed' $Hash;$s.TargetSid=$sid;$s.TargetUserName='fixture';$s.Phase=$Phase;return $s}
function Context {return @{MachineGuid='fixture-machine';Sid=$sid;ProfilePath=$fixture;RegisteredProfile=$fixture;ImageState='IMAGE_STATE_COMPLETE';DesktopOwned=$true;IsAdministrator=$true;OobeApiSucceeded=$true;OobeComplete=$true}}
$cases=@(
 @{Name='read-failed';Api=$false;Done=$false},@{Name='contradictory';Api=$false;Done=$true},@{Name='incomplete';Api=$true;Done=$false},
 @{Name='both-missing';Missing=@('OobeApiSucceeded','OobeComplete')},@{Name='api-missing';Done=$true;Missing=@('OobeApiSucceeded')},@{Name='done-missing';Api=$true;Missing=@('OobeComplete')},
 @{Name='api-null';Api=$null;Done=$true},@{Name='done-null';Api=$true;Done=$null},@{Name='api-int';Api=1;Done=$true},@{Name='done-int';Api=$true;Done=1},
 @{Name='api-string';Api='True';Done=$true},@{Name='done-string';Api=$true;Done='True'},@{Name='api-false-string';Api='False';Done=$true},@{Name='done-false-string';Api=$true;Done='False'},
 @{Name='api-switch';Api=[Management.Automation.SwitchParameter]::new($true);Done=$true},@{Name='done-array';Api=$true;Done=@($true,$true)}
)
$index=0
foreach($phase in @('AwaitingLogon','ApplyPending','SshPending','Complete','AccountConfirmed')){
 foreach($case in $cases){
  $index++;$folder=Join-Path $fixture ('n'+$index);[void][IO.Directory]::CreateDirectory($folder);$path=Join-Path $folder 'state.json';$state=State $phase;[IO.File]::WriteAllText($path,($state|ConvertTo-Json),[Text.UTF8Encoding]::new($false));$before=[IO.File]::ReadAllText($path)
  $context=Context;$context.OobeApiSucceeded=$case.Api;$context.OobeComplete=$case.Done;foreach($field in @($case.Missing)) {if($null -ne $field){$context.Remove($field)}}
  $script:aclWrites=0;$script:messages.Clear();$script:accountReads=0;$failure=$null
  try{Confirm-InitAccountCheckpoint $state $path $context $hash}catch{$failure=$_}
  Assert ($failure -and $script:aclWrites -eq 0 -and $script:messages.Count -eq 0 -and $script:accountReads -eq 0 -and $state.Phase -ceq $phase -and [IO.File]::ReadAllText($path) -ceq $before -and -not(Test-Path -LiteralPath (Join-Path $folder 'state_before_account_confirmation.json'))) ('原checkpoint拒絕非bool雙true且零Save/零成功文案：'+$phase+'/'+$case.Name)
 }
}
foreach($phase in @('AwaitingLogon','ApplyPending','SshPending','Complete','AccountConfirmed')){
 $folder=Join-Path $fixture ('p'+$phase);[void][IO.Directory]::CreateDirectory($folder);$path=Join-Path $folder 'state.json';$state=State $phase;$state.LastErrorCode='historical-marker';[IO.File]::WriteAllText($path,($state|ConvertTo-Json),[Text.UTF8Encoding]::new($false));$script:aclWrites=0;$script:messages.Clear()
 Confirm-InitAccountCheckpoint $state $path (Context) $hash
 $expected=if($phase -ceq 'AccountConfirmed'){0}else{2};$snapshot=Join-Path $folder 'state_before_account_confirmation.json'
 Assert ($state.Phase -ceq 'AccountConfirmed' -and $script:aclWrites -eq $expected -and $script:messages.Count -eq 1) ('原生bool雙true的既有schema1階段可續跑、不建立帳密：'+$phase)
 if($phase -cne 'AccountConfirmed'){$old=Read-InitProvisioningState $snapshot 'fixture-machine' $hash;Assert ($old.Phase -ceq $phase -and $old.PackageHash -ceq $hash -and $old.LastErrorCode -ceq 'historical-marker') ('舊快照原hash/schema保留：'+$phase)}
}
# Execute the original Windows entry and original native-context aggregator against native boundaries only.
$script:nativeApiCalls=0;$script:nativeSucceeded=$true;$script:nativeComplete=$true;$script:nativeThrows=$false
function Get-InitIdentityContext {return @{Sid=$sid;IsAdministrator=$true;SessionId=3}}
function Get-CimInstance {param($ClassName,$Filter,$ErrorAction) if($ClassName -eq 'Win32_OperatingSystem'){return [pscustomobject]@{BuildNumber='26200';ProductType=1}};if($ClassName -eq 'Win32_Process'){return [pscustomobject]@{Name='explorer.exe';SessionId=3}};throw 'unexpected native CIM read'}
function Invoke-CimMethod {param($InputObject,$MethodName,$ErrorAction) [pscustomobject]@{Sid=$sid}}
function Get-ItemProperty {param($LiteralPath,$ErrorAction) switch($LiteralPath){'HKLM:\SYSTEM\Setup'{return [pscustomobject]@{OOBEInProgress=0;SystemSetupInProgress=0}} 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State'{return [pscustomobject]@{ImageState='IMAGE_STATE_COMPLETE'}} 'HKLM:\SOFTWARE\Microsoft\Cryptography'{return [pscustomobject]@{MachineGuid='fixture-machine'}} default{if($LiteralPath -like '*\ProfileList\*'){return [pscustomobject]@{ProfileImagePath=$env:USERPROFILE}};throw 'unexpected native registry read'}}}
function Invoke-InitOobeCompleteNative {$script:nativeApiCalls++;if($script:nativeThrows){throw [IO.IOException]::new('controlled native OOBE read error')};[pscustomobject]@{Succeeded=$script:nativeSucceeded;Complete=$script:nativeComplete}}
$stage=Join-Path $fixture 'stage';$assets=Join-Path $stage 'runtime/modules/init/assets';[void][IO.Directory]::CreateDirectory($assets)
foreach($name in @('hide_oobe.xml','hide_oobe.ppkg','provenance.json')){Copy-Item -LiteralPath (Join-Path $root ('modules/init/assets/'+$name)) -Destination (Join-Path $assets $name)}
$assetHash=(Get-FileHash -LiteralPath (Join-Path $assets 'hide_oobe.ppkg')).Hash;$path=Join-Path $stage 'state.json';$oldProfile=$env:USERPROFILE
try{
 $env:USERPROFILE=$fixture
 foreach($phase in @('AwaitingLogon','Complete','AccountConfirmed')){
  foreach($mode in @('failed','incomplete','throw')){
   $state=State $phase $assetHash;[IO.File]::WriteAllText($path,($state|ConvertTo-Json),[Text.UTF8Encoding]::new($false));$before=[IO.File]::ReadAllText($path);$script:nativeSucceeded=$mode -ne 'failed';$script:nativeComplete=$mode -eq 'throw';$script:nativeThrows=$mode -eq 'throw';$script:aclWrites=0;$script:messages.Clear();$calls=$script:nativeApiCalls;$failure=$null
   try{Invoke-InitWindowsCheckpoint -StageRoot $stage|Out-Null}catch{$failure=$_}
   Assert ($failure -and $script:nativeApiCalls -eq $calls+1 -and $script:aclWrites -eq 0 -and $script:messages.Count -eq 0 -and [IO.File]::ReadAllText($path) -ceq $before) ('Windows入口實際重新讀原生現況，不信舊receipt：'+$phase+'/'+$mode)
  }
 }
 $script:nativeSucceeded=$true;$script:nativeComplete=$true;$script:nativeThrows=$false;$state=State 'Complete' $assetHash;[IO.File]::WriteAllText($path,($state|ConvertTo-Json),[Text.UTF8Encoding]::new($false));$script:aclWrites=0;$script:messages.Clear()
 Assert (Invoke-InitWindowsCheckpoint -StageRoot $stage) '舊Init的原PPKG資產與schema1狀態可直接接新Windows checkpoint'
 $confirmed=Read-InitProvisioningState $path 'fixture-machine' $assetHash;$old=Read-InitProvisioningState (Join-Path $stage 'state_before_account_confirmation.json') 'fixture-machine' $assetHash
 Assert ($confirmed.Phase -ceq 'AccountConfirmed' -and $confirmed.SchemaVersion -eq 1 -and $old.Phase -ceq 'Complete' -and $old.PackageHash -ceq $assetHash -and $old.SourceRoot -ceq 'old USB removed') '跨版本續跑不把原PPKG hash換成新source hash，不重設帳號'
 $script:aclWrites=0;$script:messages.Clear()
 Assert (-not(Invoke-InitWindowsCheckpoint -StageRoot (Join-Path $fixture 'absent-stage'))) '舊Audit沒有provisioning stage保持安全no-op'
 Assert ($script:aclWrites -eq 0 -and $script:messages.Count -eq 0) '舊Audit no-op不產生狀態或成功文案'
}finally{$env:USERPROFILE=$oldProfile}
