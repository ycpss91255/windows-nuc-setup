#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/init/provisioning_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
function Reject([scriptblock]$Action,[string]$Expected,[string]$Name){$failure=$null;try{& $Action|Out-Null}catch{$failure=$_};Assert ($failure -and $failure.Exception -isnot [Management.Automation.ParameterBindingException] -and $failure.Exception.Message.Contains($Expected)) ($Name+'; actual='+$failure.Exception.Message)}
function Clone($v){$v|ConvertTo-Json -Depth 8|ConvertFrom-Json}
$fixture=Join-Path $env:TEMP ('provision_gaps_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
$fixture=[IO.Path]::GetFullPath($fixture)
$identity=Get-InitIdentityContext;Assert ($identity.Sid -and $identity.IsAdministrator -is [bool]) '真實權杖只讀身分查詢，不提權'
# The SDK does not publish a minimum Server version for this native API.
# Substitute only the native type compiler boundary; execute the original wrapper twice.
$script:GapNativeAddType=Get-Command Add-Type
$script:GapOobeTypeCompilations=0
function Add-Type {
 param($TypeDefinition)
 if($TypeDefinition -notmatch 'DllImport\("kernel32\.dll"' -or $TypeDefinition -notmatch 'extern bool OOBEComplete') {throw 'unexpected native compilation'}
 $script:GapOobeTypeCompilations++
 & $script:GapNativeAddType -TypeDefinition 'namespace WindowsSetup { public static class InitOobeNative { public static bool OOBEComplete(out bool complete) {complete=true; return true;} } }'
}
$native=Invoke-InitOobeCompleteNative;$again=Invoke-InitOobeCompleteNative;Assert ($native.Succeeded -is [bool] -and $again.Complete -is [bool]) '原始OOBEComplete只讀原生API及已載入型別路徑'
# Native Client API double. Real asset file/hash/XML validation is unchanged.
function Get-ProvisioningPackage {
 param([switch]$AllInstalledPackages,$PackagePath,$LogsDirectoryPath,$ErrorAction)
 if($PackagePath){
  if([IO.Path]::GetFileName($PackagePath) -cne 'hide_oobe.ppkg' -or -not(Microsoft.PowerShell.Management\Test-Path -LiteralPath $PackagePath -PathType Leaf)){throw 'unexpected metadata input'}
  return [pscustomobject]@{PackageID='1c2605ea-96ae-42fc-8f11-45fc0cb9d133';PackageName='windows_setup_hide_oobe';Version='1.0';Rank=0;OwnerType=5000;IsInstalled=$false}
 }
 if($AllInstalledPackages -and $script:installed){[pscustomobject]@{IsInstalled=$true;PackageID='1c2605ea-96ae-42fc-8f11-45fc0cb9d133';Version='1.0';PackageName='windows_setup_hide_oobe';Rank=0;OwnerType=5000}}
}
Assert ($script:GapOobeTypeCompilations -eq 1) '原始native wrapper只建立一次受控OS API型別，不依Server匯出'
$assetRoot=Join-Path $root 'modules/init/assets';$asset=Assert-InitProvisioningAsset $assetRoot;$hash=$asset.PackageSHA256
$sid='S-1-5-21-1-2-3-1001';$script:aclMap=@{};$script:aclMode='good';$script:users=@{};$script:members=@();$script:accountMode='normal';$script:groupWrites=0;$script:installed=$true;$script:installEffect=$true;$script:installs=0
function NewAcl([bool]$Directory){$a=if($Directory){[Security.AccessControl.DirectorySecurity]::new()}else{[Security.AccessControl.FileSecurity]::new()};$a.SetAccessRuleProtection($true,$false);$a.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'));foreach($id in @('S-1-5-18','S-1-5-32-544')){$flags=if($Directory){'ContainerInherit,ObjectInherit'}else{'None'};$a.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($id),'FullControl',$flags,'None','Allow'))};return $a}
function Get-Acl {param($LiteralPath,$ErrorAction) if(-not ([IO.Path]::GetFullPath($LiteralPath)).StartsWith($fixture,[StringComparison]::OrdinalIgnoreCase)){throw 'fixture ACL outside TEMP'};if($script:aclMap.ContainsKey($LiteralPath)){return $script:aclMap[$LiteralPath]};$dir=Microsoft.PowerShell.Management\Test-Path -LiteralPath $LiteralPath -PathType Container;$a=NewAcl $dir;if($LiteralPath.EndsWith('.cmd')){$a.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-5-32-545'),'ReadAndExecute','Allow'))};return $a}
function Set-Acl {param($LiteralPath,$AclObject,$ErrorAction) if(-not ([IO.Path]::GetFullPath($LiteralPath)).StartsWith($fixture,[StringComparison]::OrdinalIgnoreCase)){throw 'fixture SetAcl outside TEMP'};$script:aclMap[$LiteralPath]=$AclObject}
function Get-LocalUser {param($SID,$Name,$ErrorAction) if($SID){if($script:accountMode -eq 'readback_bad'){return [pscustomobject]@{SID=[pscustomobject]@{Value=$SID};Name='fixture';Enabled=$false}};return $script:users[[string]$SID]};$script:users.Values|Where-Object Name -eq $Name}
function New-LocalUser {param($Name,$Password,$ErrorAction) $value=if($script:accountMode -eq 'new_sid_bad'){'invalid'}else{$sid};$u=[pscustomobject]@{SID=[pscustomobject]@{Value=$value};Name=$Name;Enabled=$true};$script:users[$value]=$u;return $u}
function Get-LocalGroupMember {param($SID,$ErrorAction) @($script:members|ForEach-Object {[pscustomobject]@{SID=[pscustomobject]@{Value=$_}}})}
function Add-LocalGroupMember {param($SID,$Member,$ErrorAction) $script:groupWrites++;if($script:accountMode -ne 'group_refused'){$script:members+=@($Member)}}
function Install-ProvisioningPackage {param($PackagePath,[switch]$QuietInstall,$ErrorAction) $script:installs++;$script:installed=$script:installEffect}
$path=Join-Path $fixture 'state.json'
function State([string]$Phase='Prepared'){$s=New-InitProvisioningState 'fixture-machine' 'TEST' $root $hash;if($Phase -ne 'Prepared'){$s.TargetSid=$sid;$s.TargetUserName='fixture'};$s.Phase=$Phase;return $s}
foreach($field in @('PackageId','PackageVersion','Phase')){$bad=State;$bad.$field='invalid';Reject {Assert-InitProvisioningState $bad 'fixture-machine' $hash} '版本或階段' ('拒絕狀態非法 '+$field)}
foreach($field in @('TargetSid','TargetUserName')){$bad=State AccountReady;$bad.$field='';Reject {Assert-InitProvisioningState $bad 'fixture-machine' $hash} '已確認' ('非Prepared必須有正式帳號 '+$field)}
Reject {New-InitProvisioningAccount (State Complete) fixture $null $path} '階段不可' '完成狀態不能重建帳號'
foreach($case in @('phase','name','password')){$s=State;if($case -eq 'phase'){$s.Phase='AccountCreated'};$pw=if($case -eq 'password'){$null}else{ConvertTo-SecureString 'fixture-pass' -AsPlainText -Force};try{Reject {New-InitProvisioningAccount $s $(if($case -eq 'name'){''}else{'fixture'}) $pw $path} '安全密碼' ('帳號建立前拒絕缺失 '+$case)}finally{if($pw){$pw.Dispose()}}}
foreach($mode in @('new_sid_bad','readback_bad','group_refused','normal')){
 $script:accountMode=$mode;$script:users=@{};$script:members=@();$script:groupWrites=0;$s=State;$pw=ConvertTo-SecureString 'fixture-pass' -AsPlainText -Force
 try{if($mode -eq 'normal'){New-InitProvisioningAccount $s fixture $pw $path;Assert ($s.Phase -eq 'AccountReady' -and $script:groupWrites -eq 1) '真帳號編排只在新SID讀回後補管理群組'}else{Reject {New-InitProvisioningAccount $s fixture $pw $path} $(switch($mode){new_sid_bad{'新帳號 SID'} readback_bad{'新帳號讀回'} group_refused{'群組 SID'}}) ('原生帳號/群組失敗不假完成 '+$mode)}}finally{$pw.Dispose()}
}
$script:accountMode='normal';$script:members=@($sid)
foreach($directory in @($true,$false)){
 $guardPath=if($directory){$fixture}else{$path}
 foreach($mode in @('owner','deny','missing')){$bad=NewAcl $directory;switch($mode){owner{$bad.SetOwner([Security.Principal.SecurityIdentifier]::new($sid))} deny{$bad.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'),'Read','Deny'))} missing{$bad.RemoveAccessRuleAll([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-5-18'),'FullControl','Allow'))}};$script:aclMap[$guardPath]=$bad;Reject {if($directory){Assert-InitProtectedDirectory $guardPath}else{Assert-InitProtectedFile $guardPath}} $(if($mode -eq 'owner'){'擁有者'}elseif($mode -eq 'deny'){'ACL'}else{'規則'}) ('真ACL拒絕 '+$directory+'/'+$mode);$script:aclMap.Remove($guardPath)}
}
$bad=NewAcl $false;$directoryAcl=[Security.AccessControl.DirectorySecurity]::new();$directoryAcl.SetAccessRuleProtection($true,$false);$directoryAcl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'));foreach($id in @('S-1-5-18','S-1-5-32-544')){$directoryAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($id),'FullControl','Allow'))};$script:aclMap[$fixture]=$directoryAcl;Reject {Assert-InitProtectedDirectory $fixture} '保護規則' '目錄FullControl仍必須子檔繼承';$script:aclMap.Remove($fixture)
$s=State AwaitingLogon;Save-InitProvisioningState $s $path;$r=Read-InitProvisioningState $path 'fixture-machine' $hash;Assert ($r.TargetSid -eq $sid) '原始受保護state讀取與真檔案JSON驗證'
$context=@{OobeApiSucceeded=$true;OobeComplete=$true;MachineGuid='fixture-machine';Sid=$sid;ImageState='IMAGE_STATE_COMPLETE';DesktopOwned=$true;IsAdministrator=$true;ProfilePath=$fixture;RegisteredProfile=$fixture}
Reject {Confirm-InitAccountCheckpoint (State AccountReady) $path $context $hash} '尚未準備' '帳號未登入階段不得完成checkpoint'
$script:users[$sid].Enabled=$false;Reject {Confirm-InitAccountCheckpoint (State AwaitingLogon) $path $context $hash} '群組驗證' 'checkpoint拒絕停用帳號';$script:users[$sid].Enabled=$true
$s=State AwaitingLogon;Confirm-InitAccountCheckpoint $s $path $context $hash;Assert ($s.Phase -eq 'AccountConfirmed') 'checkpoint建立無密碼快照後確認'
$s=State AwaitingLogon;Confirm-InitAccountCheckpoint $s $path $context $hash;Assert ($s.Phase -eq 'AccountConfirmed') '既有相同SID快照可安全續跑'
$snapshot=Join-Path $fixture 'state_before_account_confirmation.json';$other=State AwaitingLogon;$other.TargetSid='S-1-5-21-1-2-3-9999';Save-InitProvisioningState $other $snapshot;Reject {Confirm-InitAccountCheckpoint (State AwaitingLogon) $path $context $hash} '快照不屬於' '不同SID快照不可覆寫'
Reject {Invoke-InitProvisioningApply (State Prepared) $path $assetRoot {$true}} '未確認正式帳號' '未確認帳號不可apply'
$script:users[$sid].Enabled=$false;Reject {Invoke-InitProvisioningApply (State AccountReady) $path $assetRoot {$true}} '正式帳號讀回' 'apply拒絕失去啟用的目標';$script:users[$sid].Enabled=$true
foreach($effect in @($false,$true)){$script:installed=$false;$script:installEffect=$effect;$s=State AccountReady;if($effect){Invoke-InitProvisioningApply $s $path $assetRoot {$true};Assert ($s.Phase -eq 'AwaitingLogon') '原生install後重新讀回已裝才清錯誤'}else{Reject {Invoke-InitProvisioningApply $s $path $assetRoot {$true}} '尚未確認設定包' '原生install沒有生效保留ApplyPending';Assert ($s.Phase -eq 'ApplyPending') '不把安裝呼叫成功當已裝'}}
foreach($values in @(@('a','b'),@("a`nb","a`nb"),@(('x'*128),('x'*128)))){$one=ConvertTo-SecureString $values[0] -AsPlainText -Force;$two=ConvertTo-SecureString $values[1] -AsPlainText -Force;try{Assert (-not(Test-InitSecurePasswordPair $one $two)) '安全密碼拒不同/控制字元/空/過長'}finally{$one.Dispose();$two.Dispose()}}
Assert (-not(Test-InitSecurePasswordPair $null $null)) 'null SecureString拒絕'
