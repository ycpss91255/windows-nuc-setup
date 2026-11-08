#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'checkpoint_native_state_tests.ps1')
. (Join-Path $root 'modules/init/init_entry_library.ps1')
. (Join-Path $root 'core/gui_stage_library.ps1')
function Get-InitIdentityContext {return @{Sid=$sid;IsAdministrator=$true;SessionId=3}}
function Invoke-InitOobeCompleteNative {[pscustomobject]@{Succeeded=$true;Complete=$true}}
function Get-SetupInitNativeIdentity {[pscustomobject]@{Sid=$sid;UserSID=$sid;IsAdministrator=$true;SessionId=3;Is64Bit=$true;Architecture='AMD64'}}
function Get-ItemProperty {param([Alias('Path')]$LiteralPath,$ErrorAction) switch($LiteralPath){'HKLM:\SYSTEM\Setup'{return [pscustomobject]@{OOBEInProgress=0;SystemSetupInProgress=0}} 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State'{return [pscustomobject]@{ImageState='IMAGE_STATE_COMPLETE'}} 'HKLM:\SOFTWARE\Microsoft\Cryptography'{return [pscustomobject]@{MachineGuid='fixture-machine'}} default{if($LiteralPath -like '*\ProfileList\*'){return [pscustomobject]@{ProfileImagePath=$env:USERPROFILE}};throw 'controlled native registry missing'}}}
function Invoke-CimMethod {param($InputObject,$MethodName,$ErrorAction) if($script:ownerThrow){throw [IO.IOException]::new('controlled owner read failed')};return $script:ownerResult}
$ownerCases=@(
 @{Name='native-failed';Result=[pscustomobject]@{ReturnValue=[uint32]5;Sid=$sid}},
 @{Name='missing-code';Result=[pscustomobject]@{Sid=$sid}},
 @{Name='string-zero';Result=[pscustomobject]@{ReturnValue='0';Sid=$sid}},
 @{Name='bool-false';Result=[pscustomobject]@{ReturnValue=$false;Sid=$sid}},
 @{Name='null-code';Result=[pscustomobject]@{ReturnValue=$null;Sid=$sid}},
 @{Name='mismatched-sid';Result=[pscustomobject]@{ReturnValue=[uint32]0;Sid='S-1-5-21-1-2-3-1002'}},
 @{Name='native-throw';Throws=$true}
)
$oldProfile=$env:USERPROFILE
try{
 $env:USERPROFILE=$fixture
 foreach($case in $ownerCases){
  $script:ownerResult=$case.Result;$script:ownerThrow=[bool]$case.Throws
  $state=State 'Complete' $assetHash;[IO.File]::WriteAllText($path,($state|ConvertTo-Json),[Text.UTF8Encoding]::new($false));$before=[IO.File]::ReadAllText($path);$script:aclWrites=0;$script:messages.Clear();$rejected=$false
  try{Invoke-InitWindowsCheckpoint -StageRoot $stage|Out-Null}catch{$rejected=$true}
  Assert ($rejected -and $script:aclWrites -eq 0 -and $script:messages.Count -eq 0 -and $state.Phase -ceq 'Complete' -and [IO.File]::ReadAllText($path) -ceq $before) ('原Windows checkpoint拒不可信owner結果且零寫入：'+$case.Name)
  $desktop=$false;try{$desktop=(Get-SetupInitContext).DesktopOwned}catch{}
  Assert (-not $desktop) ('F10/Init原context拒不可信owner：'+$case.Name)
  $rejected=$false;try{Get-SetupGuiDesktopSession -Scope ([pscustomobject]@{SessionId=3;UserSID=$sid})|Out-Null}catch{$rejected=$true}
  Assert $rejected ('GUI原派送拒不可信owner：'+$case.Name)
 }
 foreach($zero in @([int]0,[uint32]0)){
  $script:ownerThrow=$false;$script:ownerResult=[pscustomobject]@{ReturnValue=$zero;Sid=$sid}
  $state=State 'Complete' $assetHash;[IO.File]::WriteAllText($path,($state|ConvertTo-Json),[Text.UTF8Encoding]::new($false));$script:aclWrites=0
  Assert (Invoke-InitWindowsCheckpoint -StageRoot $stage) ('原Windows checkpoint接受真整數0及同SID：'+$zero.GetType().Name)
  Assert ((Get-SetupInitContext).DesktopOwned) ('F10/Init接受真整數0及同SID：'+$zero.GetType().Name)
  Assert ((Get-SetupGuiDesktopSession -Scope ([pscustomobject]@{SessionId=3;UserSID=$sid})) -eq 3) ('GUI接受真整數0及同SID：'+$zero.GetType().Name)
 }
}finally{$env:USERPROFILE=$oldProfile}