#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/init/provisioning_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
function Reject([scriptblock]$Action,[string]$Expected,[string]$Name){$f=$null;try{& $Action|Out-Null}catch{$f=$_};Assert ($f -and $f.Exception -isnot [Management.Automation.ParameterBindingException] -and $f.Exception.Message.Contains($Expected)) ($Name+'; actual='+$f.Exception.Message)}
# Native Client API double. Real asset file/hash/XML validation is unchanged.
function Get-ProvisioningPackage {
 param([switch]$AllInstalledPackages,$PackagePath,$LogsDirectoryPath,$ErrorAction)
 if($PackagePath){
  if([IO.Path]::GetFileName($PackagePath) -cne 'hide_oobe.ppkg' -or -not(Microsoft.PowerShell.Management\Test-Path -LiteralPath $PackagePath -PathType Leaf)){throw 'unexpected metadata input'}
  return [pscustomobject]@{PackageID='1c2605ea-96ae-42fc-8f11-45fc0cb9d133';PackageName='windows_setup_hide_oobe';Version='1.0';Rank=0;OwnerType=5000;IsInstalled=$false}
 }
 if($AllInstalledPackages -and $script:installed){[pscustomobject]@{IsInstalled=$true;PackageID='1c2605ea-96ae-42fc-8f11-45fc0cb9d133';Version='1.0';PackageName='windows_setup_hide_oobe';Rank=0;OwnerType=5000}}
}
$fixture=Join-Path $env:TEMP ('provision_context_gaps_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
$fixture=[IO.Path]::GetFullPath($fixture)
$stage=Join-Path $fixture 'stage';[void][IO.Directory]::CreateDirectory($stage)
$script:gapIdentity=@{Sid='S-1-5-21-1-2-3-1001';IsAdministrator=$true;SessionId=1};$script:complete=$true;$script:aclReads=0
function Get-InitIdentityContext {$script:gapIdentity}
function Invoke-InitOobeCompleteNative {[pscustomobject]@{Succeeded=$true;Complete=$script:complete;ErrorCode=0}}
function Get-CimInstance {param($ClassName,$Filter,$ErrorAction) if($ClassName -eq 'Win32_OperatingSystem'){[pscustomobject]@{BuildNumber='22631';ProductType=1}}else{[pscustomobject]@{Name='explorer.exe';SessionId=1}}}
function Invoke-CimMethod {param($InputObject,$MethodName,$ErrorAction) [pscustomobject]@{ReturnValue=0;Sid=$script:gapIdentity.Sid}}
function Get-ItemProperty {param($LiteralPath,$ErrorAction) if($LiteralPath -like '*ProfileList*'){[pscustomobject]@{ProfileImagePath=$env:USERPROFILE}}elseif($LiteralPath -like '*Cryptography'){[pscustomobject]@{MachineGuid='fixture-machine'}}elseif($LiteralPath -like '*Setup\State'){[pscustomobject]@{ImageState='IMAGE_STATE_COMPLETE'}}else{[pscustomobject]@{OOBEInProgress=1;SystemSetupInProgress=1}}}
function Get-Acl {param($LiteralPath,$ErrorAction) $script:aclReads++;if(-not ([IO.Path]::GetFullPath($LiteralPath)).StartsWith($fixture)){throw 'ACL outside fixture'};$dir=(Get-Item -LiteralPath $LiteralPath).PSIsContainer;$a=if($dir){[Security.AccessControl.DirectorySecurity]::new()}else{[Security.AccessControl.FileSecurity]::new()};$a.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'));$a.SetAccessRuleProtection($true,$false);foreach($id in @('S-1-5-18','S-1-5-32-544')){$a.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new($id),'FullControl',$(if($dir){'ContainerInherit,ObjectInherit'}else{'None'}),'None','Allow'))};return $a}
function New-LocalUser {throw 'forbidden account creation'}
function Install-ProvisioningPackage {throw 'forbidden package installation'}
function Add-LocalGroupMember {throw 'forbidden group change'}
function Start-Process {throw 'forbidden elevation/process'}
$context=Get-InitProvisioningContext;Assert ($context.DesktopOwned -and $context.RegisteredProfile -eq $env:USERPROFILE -and $context.OobeComplete) '原始context彙整原生身分/桌面與OOBE facts，不改host'
Reject {Invoke-InitProvisioningEntry $root $stage -ResumeStatePath (Join-Path $fixture 'wrong.json')} '狀態位置不符' '原始入口拒絕另一續跑狀態位置'
$script:gapIdentity.Sid='S-1-5-18';[IO.File]::WriteAllText((Join-Path $stage 'state.json'),'inert existing marker')
Reject {Invoke-InitProvisioningEntry $root $stage} '不是可確認' 'SYSTEM既有state選staged runtime仍先拒絕已完成OOBE'
Remove-Item -LiteralPath (Join-Path $stage 'state.json')
$script:gapIdentity.Sid='S-1-5-21-1-2-3-1001';$script:gapIdentity.IsAdministrator=$false
Reject {Invoke-InitProvisioningEntry $root $stage -ResumeStatePath (Join-Path $stage 'state.json')} '公開 windows_setup_init.cmd' '非管理員帶續跑位置不能存取私有state'
Assert ($script:aclReads -eq 0) '拒絕在私有ACL讀取之前發生'
$script:gapIdentity.IsAdministrator=$true;Assert (-not(Invoke-InitProvisioningEntry $root $stage)) '沒有state的一般管理員不創造初始化狀態'
$assets=Join-Path $stage 'runtime/modules/init/assets';[void][IO.Directory]::CreateDirectory($assets)
foreach($name in @('hide_oobe.xml','hide_oobe.ppkg','provenance.json')){Copy-Item -LiteralPath (Join-Path $root ('modules/init/assets/'+$name)) -Destination (Join-Path $assets $name)}
$asset=Assert-InitProvisioningAsset $assets;$state=New-InitProvisioningState 'fixture-machine' 'TEST' $root $asset.PackageSHA256
$state|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $stage 'state.json') -Encoding UTF8
Reject {Invoke-InitProvisioningEntry $root $stage -ResumeStatePath (Join-Path $stage 'state.json')} '不是本輪建立' '未確認目標SID的state不能被正式帳號接手'
$script:gapIdentity.IsAdministrator=$false;Reject {Invoke-InitWindowsCheckpoint $stage} '管理員權限' 'Windows checkpoint拒絕標準token'
$script:gapIdentity.IsAdministrator=$true;$script:gapIdentity.Sid='S-1-5-18';Reject {Invoke-InitWindowsCheckpoint $stage} '管理員權限' 'Windows checkpoint拒絕SYSTEM'
$script:gapIdentity.Sid='S-1-5-21-1-2-3-1001';Remove-Item -LiteralPath (Join-Path $stage 'state.json');Reject {Invoke-InitWindowsCheckpoint $stage} '已有 Init 暫存但缺少狀態' '有stage無state不略過未完成初始化'
