#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'checkpoint_native_state_tests.ps1')
. (Join-Path $root 'modules/init/init_entry_library.ps1')
. (Join-Path $root 'core/gui_stage_library.ps1')
function Get-InitIdentityContext {return @{Sid=$sid;IsAdministrator=$true;SessionId=3}}
function Invoke-InitOobeCompleteNative {[pscustomobject]@{Succeeded=$true;Complete=$true}}
function Get-SetupInitNativeIdentity {[pscustomobject]@{Sid=$sid;UserSID=$sid;IsAdministrator=$true;SessionId=3;Is64Bit=$true;Architecture='AMD64'}}
function Get-ItemProperty {param([Alias('Path')]$LiteralPath,$ErrorAction) switch($LiteralPath){'HKLM:\SYSTEM\Setup'{return [pscustomobject]@{OOBEInProgress=0;SystemSetupInProgress=0}} 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State'{return [pscustomobject]@{ImageState='IMAGE_STATE_COMPLETE'}} 'HKLM:\SOFTWARE\Microsoft\Cryptography'{return [pscustomobject]@{MachineGuid='fixture-machine'}} default{if($LiteralPath -like '*\ProfileList\*'){return [pscustomobject]@{ProfileImagePath=$env:USERPROFILE}};throw 'controlled native registry missing'}}}
function Invoke-CimMethod {param($InputObject,$MethodName,$ErrorAction) if($global:OwnerStatusFixtureThrow){throw [IO.IOException]::new('controlled owner read failed')};return $global:OwnerStatusFixtureResult}
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
  $global:OwnerStatusFixtureResult=$case.Result;$global:OwnerStatusFixtureThrow=[bool]$case.Throws
  $state=State 'Complete' $assetHash;[IO.File]::WriteAllText($path,($state|ConvertTo-Json),[Text.UTF8Encoding]::new($false));$before=[IO.File]::ReadAllText($path);$script:aclWrites=0;$script:messages.Clear();$rejected=$false
  try{Invoke-InitWindowsCheckpoint -StageRoot $stage|Out-Null}catch{$rejected=$true}
  Assert ($rejected -and $script:aclWrites -eq 0 -and $script:messages.Count -eq 0 -and $state.Phase -ceq 'Complete' -and [IO.File]::ReadAllText($path) -ceq $before) ('原Windows checkpoint拒不可信owner結果且零寫入：'+$case.Name)
  $desktop=$false;try{$desktop=(Get-SetupInitContext).DesktopOwned}catch{}
  Assert (-not $desktop) ('F10/Init原context拒不可信owner：'+$case.Name)
  $rejected=$false;try{Get-SetupGuiDesktopSession -Scope ([pscustomobject]@{SessionId=3;UserSID=$sid})|Out-Null}catch{$rejected=$true}
  Assert $rejected ('GUI原派送拒不可信owner：'+$case.Name)
 }
 foreach($zero in @([int]0,[uint32]0)){
  $global:OwnerStatusFixtureThrow=$false;$global:OwnerStatusFixtureResult=[pscustomobject]@{ReturnValue=$zero;Sid=$sid}
  $state=State 'Complete' $assetHash;[IO.File]::WriteAllText($path,($state|ConvertTo-Json),[Text.UTF8Encoding]::new($false));$script:aclWrites=0
  Assert (Invoke-InitWindowsCheckpoint -StageRoot $stage) ('原Windows checkpoint接受真整數0及同SID：'+$zero.GetType().Name)
  Assert ((Get-SetupInitContext).DesktopOwned) ('F10/Init接受真整數0及同SID：'+$zero.GetType().Name)
  Assert ((Get-SetupGuiDesktopSession -Scope ([pscustomobject]@{SessionId=3;UserSID=$sid})) -eq 3) ('GUI接受真整數0及同SID：'+$zero.GetType().Name)
 }
}finally{$env:USERPROFILE=$oldProfile}
function Write-Host {param($Object,$ForegroundColor)}
# Run the entire shared Windows preflight with a controlled native SID boundary.
. (Join-Path $root 'core/prerequisites_library.ps1')
$preflightSid='S-1-5-21-1-2-3-1001'
$preflightUserSid=[Security.Principal.SecurityIdentifier]::new($preflightSid)
$global:OwnerPreflightFixture=[pscustomobject]@{Build=26200;Edition='Professional';Image='IMAGE_STATE_COMPLETE';LocalEnabled=$true;LocalMissing=$false;LocalMismatch=$false;MissingCommand=$false}
$global:OwnerPreflightActualEntrySid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
function Get-LocalUser {param($SID,$ErrorAction) $script:accountReads++;if($global:OwnerPreflightFixture.LocalMissing -or $SID.Value -notin @('S-1-5-21-1-2-3-1001',$global:OwnerPreflightActualEntrySid)){throw 'controlled local account missing'};[pscustomobject]@{Name='fixture';SID=[Security.Principal.SecurityIdentifier]::new($(if($global:OwnerPreflightFixture.LocalMismatch){'S-1-5-21-1-2-3-9999'}else{$SID.Value}));Enabled=$global:OwnerPreflightFixture.LocalEnabled}}
function Get-CimInstance {param($ClassName,$Filter,$ErrorAction) switch($ClassName){'Win32_BaseBoard'{[pscustomobject]@{Product='unregistered-fixture'}} 'Win32_OperatingSystem'{[pscustomobject]@{BuildNumber=$global:OwnerPreflightFixture.Build}} 'Win32_Process'{[pscustomobject]@{SessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId}} default{throw 'unexpected preflight CIM class'}}}
function Get-ItemProperty {param([Alias('Path')]$LiteralPath,$ErrorAction) switch($LiteralPath){'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'{[pscustomobject]@{EditionID=$global:OwnerPreflightFixture.Edition}} 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State'{[pscustomobject]@{ImageState=$global:OwnerPreflightFixture.Image}} default{throw 'unexpected preflight registry read'}}}
function Get-Command {param($Name,$ErrorAction) if($Name -in @('wt.exe','winget.exe')){if($global:OwnerPreflightFixture.MissingCommand){return $null};return [pscustomobject]@{Name=$Name}};Microsoft.PowerShell.Core\Get-Command -Name $Name -ErrorAction $ErrorAction}
function Test-Path {param($LiteralPath,$Path,$PathType) $value=if($LiteralPath){$LiteralPath}else{$Path};if([IO.Path]::GetFileName($value) -eq 'Autologon64.exe'){return $true};if($PathType){Microsoft.PowerShell.Management\Test-Path -LiteralPath $value -PathType $PathType}else{Microsoft.PowerShell.Management\Test-Path -LiteralPath $value}}
foreach($case in $ownerCases){
 $global:OwnerStatusFixtureThrow=[bool]$case.Throws
 $global:OwnerStatusFixtureResult=if($null -eq $case.Result){$null}else{$case.Result.PSObject.Copy()}
 if($global:OwnerStatusFixtureResult -and $case.Name -ne 'mismatched-sid'){$global:OwnerStatusFixtureResult.Sid=$preflightSid}
 $errorRecord=$null
 try{Assert-SetupWindowsPrerequisites -UserSid $preflightUserSid -SourceRoot $root|Out-Null}catch{$errorRecord=$_}
 Assert ($errorRecord -and ($errorRecord.Exception.Message -like '*目前登入桌面*' -or ($case.Name -eq 'native-throw' -and $errorRecord.Exception -is [IO.IOException]))) ('原Windows前置檢查在owner邊界拒絕：'+$case.Name)
}
$global:OwnerStatusFixtureThrow=$false;$global:OwnerStatusFixtureResult=[pscustomobject]@{ReturnValue=[uint32]0;Sid=$preflightSid}
Assert-SetupWindowsPrerequisites -UserSid $preflightUserSid -SourceRoot $root|Out-Null
Assert $true '完整Windows前置檢查接受原生UInt32成功碼及正式帳號SID，無系統寫入'# Forbidden built-in identities must be rejected before looking up an account or owner.
foreach($blockedSid in @('S-1-5-18','S-1-5-21-1-2-3-500')){
 $script:accountReads=0;$script:aclWrites=0;$global:OwnerStatusFixtureThrow=$true;$failure=$null
 try{Assert-SetupWindowsPrerequisites -UserSid ([Security.Principal.SecurityIdentifier]::new($blockedSid)) -SourceRoot $root|Out-Null}catch{$failure=$_}
 Assert ($failure -and $failure.Exception.Message -like '*Windows 流程不可在 SYSTEM*' -and $script:accountReads -eq 0 -and $script:aclWrites -eq 0) '完整Windows前置檢查仍在owner之前拒絕SYSTEM及Builtin500且零寫入'
}
$failure=$null
try{Assert-SetupWindowsPrerequisites -UserSid $null -SourceRoot $root|Out-Null}catch{$failure=$_}
Assert ($failure -and $script:accountReads -eq 0 -and $script:aclWrites -eq 0) '完整Windows前置檢查拒絕null SID且零寫入'
# Verify the real entry uses native identity and the same complete guard, with no identity CLI override.
$entry=[IO.File]::ReadAllText((Join-Path $root 'core/test_setup_prerequisites.ps1'))
$tokens=$null;$parseErrors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($entry,[ref]$tokens,[ref]$parseErrors)
$shared=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Assert-SetupWindowsPrerequisites'},$true))
Assert ($parseErrors.Count -eq 0 -and $shared.Count -eq 1 -and $shared[0].Extent.Text -match '-UserSid\s+\$identity.User' -and $entry -match '\$identity=\[Security.Principal.WindowsIdentity\]::GetCurrent\(\)' -and @($ast.ParamBlock.Parameters|Where-Object {$_.Name.VariablePath.UserPath -match 'Identity|UserSid'}).Count -eq 0) '正常Windows入口直接讀原生WindowsIdentity並呼叫同一完整守門，沒有身分覆寫參數'
foreach($unknownSid in @('S-1-5-21-1-2-3-9999','S-1-5-32-544')){
 $global:OwnerStatusFixtureThrow=$true;$script:aclWrites=0;$failure=$null
 try{Assert-SetupWindowsPrerequisites -UserSid ([Security.Principal.SecurityIdentifier]::new($unknownSid)) -SourceRoot $root|Out-Null}catch{$failure=$_}
 Assert ($failure -and $failure.Exception.Message -eq 'controlled local account missing' -and $script:aclWrites -eq 0) '完整Windows前置檢查拒絕不是本機正式帳號的有效SID且零寫入'
}
$global:OwnerStatusFixtureThrow=$false;$global:OwnerStatusFixtureResult=[pscustomobject]@{ReturnValue=[uint32]0;Sid=$preflightSid}
foreach($guard in @('Build','Edition','Image','LocalEnabled','LocalMissing','LocalMismatch','MissingCommand')){
 $old=$global:OwnerPreflightFixture.$guard
 $global:OwnerPreflightFixture.$guard=switch($guard){'Build'{22000};'Edition'{'Core'};'Image'{'IMAGE_STATE_UNDEPLOYABLE'};'LocalEnabled'{$false};default{$true}}
 $failure=$null;$script:aclWrites=0
 try{Assert-SetupWindowsPrerequisites -UserSid $preflightUserSid -SourceRoot $root|Out-Null}catch{$failure=$_}finally{$global:OwnerPreflightFixture.$guard=$old}
 Assert ($failure -and $script:aclWrites -eq 0) ('共用完整Windows前置檢查保留原守門：'+$guard)
}
# The normal entry still obtains the real runner SID; Builtin500/SYSTEM is expected to fail here.
$global:OwnerStatusFixtureResult=[pscustomobject]@{ReturnValue=[uint32]0;Sid=$global:OwnerPreflightActualEntrySid}
$failure=$null
try{& (Join-Path $root 'core/test_setup_prerequisites.ps1')|Out-Null}catch{$failure=$_}
$nativeBlocked=$global:OwnerPreflightActualEntrySid -eq 'S-1-5-18' -or $global:OwnerPreflightActualEntrySid -match '-500$'
Assert (($nativeBlocked -and $failure -and $failure.Exception.Message -like '*Windows 流程不可在 SYSTEM*') -or (-not $nativeBlocked -and -not $failure)) '原Windows入口仍使用真runner身份：內建帳號明確拒絕，正常帳號經同完整守門'
$global:OwnerStatusFixtureThrow=$true
& (Join-Path $root 'core/test_setup_prerequisites.ps1') -PackageOnly -HardwareProfile Generic|Out-Null
Assert $true '原PackageOnly入口不讀取owner或套用系統設定'