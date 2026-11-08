#Requires -Version 5.1
# Definitions only: loading this file never creates accounts or applies a package.
. (Join-Path $PSScriptRoot 'oobe_library.ps1')
. (Join-Path $PSScriptRoot 'provisioning_asset_library.ps1')
. (Join-Path $PSScriptRoot 'provisioning_launcher_library.ps1')
function Test-InitProvisioningContext {
 param([string]$Sid,[int]$Build,[int]$ProductType,[bool]$Is64Bit,[bool]$IsWinPE,[int]$OobeInProgress,[int]$SetupInProgress,[bool]$OobeProcessInSession,[bool]$OobeApiSucceeded,[bool]$OobeComplete)
 return ($Sid -eq 'S-1-5-18' -and $Build -ge 22621 -and $ProductType -eq 1 -and $Is64Bit -and -not $IsWinPE -and $OobeApiSucceeded -and -not $OobeComplete)
}
function New-InitProvisioningState {
 param([string]$MachineGuid,[string]$ComputerName,[string]$SourceRoot,[string]$PackageHash)
 return [pscustomobject][ordered]@{SchemaVersion=1;MachineGuid=$MachineGuid;ComputerName=$ComputerName;SourceRoot=$SourceRoot;PackageHash=$PackageHash;PackageId='1c2605ea-96ae-42fc-8f11-45fc0cb9d133';PackageVersion='1.0';TargetUserName='';TargetSid='';Phase='Prepared';LastErrorCode='';UpdatedUtc=[DateTime]::UtcNow.ToString('o')}
}
function Assert-InitProvisioningState {
 param($State,[string]$MachineGuid,[string]$PackageHash)
 $fields=@('SchemaVersion','MachineGuid','ComputerName','SourceRoot','PackageHash','PackageId','PackageVersion','TargetUserName','TargetSid','Phase','LastErrorCode','UpdatedUtc')
 if($null -eq $State -or @($State.PSObject.Properties.Name).Count -ne $fields.Count -or @($State.PSObject.Properties.Name|Where-Object {$_ -notin $fields}).Count){throw 'Init 狀態欄位不符，拒絕讀取未知或機密欄位。'}
 if($State.SchemaVersion -ne 1 -or [string]::IsNullOrWhiteSpace($MachineGuid) -or $State.MachineGuid -cne $MachineGuid -or $PackageHash -notmatch '^[a-fA-F0-9]{64}$' -or $State.PackageHash -ine $PackageHash){throw 'Init 狀態不屬於此機器或設定包。'}
 if($State.PackageId -ne '1c2605ea-96ae-42fc-8f11-45fc0cb9d133' -or $State.PackageVersion -ne '1.0' -or $State.Phase -notin @('Prepared','AccountCreated','AccountReady','AwaitingConsent','ApplyPending','AwaitingLogon','SshPending','Complete','AccountConfirmed')){throw 'Init 狀態版本或階段無效。'}
 if($State.Phase -ne 'Prepared' -and ($State.TargetSid -notmatch '^S-1-5-21-\d+-\d+-\d+-\d+$' -or [string]::IsNullOrWhiteSpace($State.TargetUserName))){throw 'Init 狀態缺少已確認的正式帳號 SID。'}
}
function New-InitProvisioningAccount {
 param($State,[string]$UserName,[Security.SecureString]$Password,[string]$StatePath)
 if($State.Phase -notin @('Prepared','AccountCreated','AccountReady')){throw '目前階段不可建立或恢復帳號。'}
 if($State.TargetSid){
  $user=Get-LocalUser -SID $State.TargetSid -ErrorAction Stop
  if(-not $user -or $user.SID.Value -ne $State.TargetSid -or $user.Name -cne $State.TargetUserName -or $UserName -cne $State.TargetUserName -or -not $user.Enabled){throw '已建立帳號的 SID、名稱或啟用狀態改變，停止恢復。'}
 }else{
  if($State.Phase -ne 'Prepared' -or [string]::IsNullOrWhiteSpace($UserName) -or $null -eq $Password -or $Password.Length -eq 0){throw '缺少有效的新帳號與安全密碼。'}
  if(Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue){throw '此帳號已存在；不重設密碼、不變更群組。'}
  $State.TargetUserName=$UserName
  Save-InitProvisioningState -State $State -StatePath $StatePath
  $user=New-LocalUser -Name $UserName -Password $Password -ErrorAction Stop
  if(-not $user -or $user.SID.Value -notmatch '^S-1-5-21-\d+-\d+-\d+-\d+$'){throw '無法取得新帳號 SID；保留帳號，停止而不盲目重建。'}
  $State.TargetSid=$user.SID.Value;$State.Phase='AccountCreated'
  Save-InitProvisioningState -State $State -StatePath $StatePath
 }
 $user=Get-LocalUser -SID $State.TargetSid -ErrorAction Stop
 if(-not $user -or $user.SID.Value -ne $State.TargetSid -or $user.Name -cne $State.TargetUserName -or -not $user.Enabled){throw '新帳號讀回驗證失敗，保留帳號並停止。'}
 $members=@(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop)
 if(-not @($members|Where-Object {$_.SID.Value -eq $State.TargetSid}).Count){Add-LocalGroupMember -SID 'S-1-5-32-544' -Member $State.TargetSid -ErrorAction Stop}
 $members=@(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop)
 if(-not @($members|Where-Object {$_.SID.Value -eq $State.TargetSid}).Count){throw '管理員群組 SID 讀回驗證失敗。'}
 $State.Phase='AccountReady';$State.LastErrorCode=''
 Save-InitProvisioningState -State $State -StatePath $StatePath
}
function Assert-InitProtectedDirectory {
 param([string]$Path)
 Assert-InitPlainPath -Path $Path
 $acl=Get-Acl -LiteralPath $Path -ErrorAction Stop
 if(-not $acl.AreAccessRulesProtected){throw 'Init 暫存目錄未停用繼承，拒絕寫入。'}
 $owner=$acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
 if($owner -notin @('S-1-5-18','S-1-5-32-544')){throw 'Init 暫存目錄擁有者不是 SYSTEM 或管理員群組。'}
 $rules=@($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
 foreach($rule in $rules){if($rule.AccessControlType -ne 'Allow' -or $rule.IdentityReference.Value -notin @('S-1-5-18','S-1-5-32-544')){throw 'Init 暫存目錄存在非預期 ACL。'}}
 foreach($sid in @('S-1-5-18','S-1-5-32-544')){
  if(-not @($rules|Where-Object {$_.IdentityReference.Value -eq $sid -and $_.FileSystemRights -eq [Security.AccessControl.FileSystemRights]::FullControl -and $_.InheritanceFlags -eq ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit) -and $_.PropagationFlags -eq [Security.AccessControl.PropagationFlags]::None}).Count){throw 'Init 暫存目錄缺少可繼承的完整保護規則。'}
 }
}
function Save-InitProvisioningState {
 param($State,[string]$StatePath)
 Assert-InitProvisioningState -State $State -MachineGuid $State.MachineGuid -PackageHash $State.PackageHash
 Assert-InitPlainPath -Path $StatePath
 Assert-InitProtectedDirectory -Path (Split-Path $StatePath -Parent)
 if(Test-Path -LiteralPath $StatePath){Assert-InitProtectedFile -Path $StatePath}
 $State.UpdatedUtc=[DateTime]::UtcNow.ToString('o')
 $temporary=$StatePath+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
 $backup=$temporary+'.previous'
 try{
  [IO.File]::WriteAllText($temporary,($State|ConvertTo-Json -Depth 3),(New-Object Text.UTF8Encoding($false)))
  Protect-InitStateFile $temporary
  Assert-InitProtectedFile $temporary
  if(Test-Path -LiteralPath $StatePath){[IO.File]::Replace($temporary,$StatePath,$backup)}else{[IO.File]::Move($temporary,$StatePath)}
  Assert-InitProtectedFile $StatePath
 }finally{foreach($path in @($temporary,$backup)){if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force}}}
}
function Protect-InitStateFile {
 param([string]$Path)
 Assert-InitPlainPath $Path
 $acl=New-Object Security.AccessControl.FileSecurity
 $acl.SetAccessRuleProtection($true,$false)
 $admin=New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
 $acl.SetOwner($admin)
 foreach($id in @('S-1-5-18','S-1-5-32-544')){
  $sid=New-Object Security.Principal.SecurityIdentifier($id)
  $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','Allow')))
 }
 Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
}
function Assert-InitProtectedFile {
 param([string]$Path)
 Assert-InitPlainPath -Path $Path
 $acl=Get-Acl -LiteralPath $Path -ErrorAction Stop
 if($acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin @('S-1-5-18','S-1-5-32-544')){throw 'Init 狀態檔擁有者不可信。'}
 $rules=@($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
 foreach($rule in $rules){if($rule.AccessControlType -ne 'Allow' -or $rule.IdentityReference.Value -notin @('S-1-5-18','S-1-5-32-544')){throw 'Init 狀態檔 ACL 允許非預期帳號，拒絕讀寫。'}}
 foreach($sid in @('S-1-5-18','S-1-5-32-544')){if(-not @($rules|Where-Object {$_.IdentityReference.Value -eq $sid -and $_.FileSystemRights -eq [Security.AccessControl.FileSystemRights]::FullControl -and -not ($_.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly)}).Count){throw 'Init 狀態檔缺少必要完整存取規則。'}}
}
function Confirm-InitAccountCheckpoint {
 param($State,[string]$StatePath,[hashtable]$Context,[string]$PackageHash)
 Assert-InitProvisioningState -State $State -MachineGuid $Context.MachineGuid -PackageHash $PackageHash
 if($State.Phase -notin @('AwaitingLogon','ApplyPending','SshPending','Complete','AccountConfirmed')){throw '帳號與 OOBE 尚未準備完成，不能進入 Windows 設定。'}
 if($Context.OobeApiSucceeded -isnot [bool] -or -not $Context.OobeApiSucceeded -or $Context.OobeComplete -isnot [bool] -or -not $Context.OobeComplete){throw '原生 OOBE 狀態尚未確認完成；保留原狀態，停止 Windows 設定。'}
 if($Context.Sid -ne $State.TargetSid -or $Context.Sid -eq 'S-1-5-18' -or $Context.ImageState -ne 'IMAGE_STATE_COMPLETE' -or -not $Context.DesktopOwned -or -not $Context.IsAdministrator){throw '請以本輪建立的正式管理員帳號登入桌面。'}
 if([string]::IsNullOrWhiteSpace($Context.ProfilePath) -or [string]::IsNullOrWhiteSpace($Context.RegisteredProfile) -or [IO.Path]::GetFullPath($Context.ProfilePath).TrimEnd('\') -ine [IO.Path]::GetFullPath($Context.RegisteredProfile).TrimEnd('\')){throw '正式帳號 SID 與家目錄登錄不一致。'}
 $user=Get-LocalUser -SID $State.TargetSid -ErrorAction Stop
 $members=@(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop)
 if(-not $user -or -not $user.Enabled -or $user.SID.Value -ne $State.TargetSid -or $user.Name -cne $State.TargetUserName -or -not @($members|Where-Object {$_.SID.Value -eq $State.TargetSid}).Count){throw '正式帳號或管理員群組驗證失敗。'}
 $installed=@(Get-ProvisioningPackage -AllInstalledPackages -ErrorAction Stop|Where-Object {$_.IsInstalled -and $_.PackageID -eq $State.PackageId -and $_.Version -eq $State.PackageVersion -and $_.PackageName -eq 'windows_setup_hide_oobe'})
 if($installed.Count -ne 1){throw '初始設定包尚未確認完成；保留原狀態，停止 Windows 設定。'}
 if($State.Phase -ne 'AccountConfirmed'){
  $snapshot=Join-Path (Split-Path $StatePath -Parent) 'state_before_account_confirmation.json'
  if(Test-Path -LiteralPath $snapshot){
   $previous=Read-InitProvisioningState $snapshot $Context.MachineGuid $PackageHash
   if($previous.TargetSid -ne $State.TargetSid){throw '既有帳號確認快照不屬於此 SID，不覆寫。'}
  }else{Save-InitProvisioningState $State $snapshot}
  $State.Phase='AccountConfirmed';$State.LastErrorCode=''
  Save-InitProvisioningState $State $StatePath
 }
 Write-Host 'Init 帳號與 OOBE 已確認；接著執行 windows.cmd。SSH 由 Windows 設定第 4 階段處理。' -ForegroundColor Green
}
function Invoke-InitProvisioningApply {
 param($State,[string]$StatePath,[string]$AssetRoot,[scriptblock]$Confirm)
 if($State.Phase -notin @('AccountReady','AwaitingConsent','ApplyPending','AwaitingLogon')){throw '未確認正式帳號，不能套用初始設定包。'}
 $asset=Assert-InitProvisioningAsset -AssetRoot $AssetRoot
 Assert-InitProvisioningState -State $State -MachineGuid $State.MachineGuid -PackageHash $asset.PackageSHA256
 $user=Get-LocalUser -SID $State.TargetSid -ErrorAction Stop
 $members=@(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop)
 if(-not $user -or -not $user.Enabled -or $user.SID.Value -ne $State.TargetSid -or $user.Name -cne $State.TargetUserName -or -not @($members|Where-Object {$_.SID.Value -eq $State.TargetSid}).Count){throw '正式帳號讀回驗證失敗，不套用初始設定包。'}
 $installed=@(Get-ProvisioningPackage -AllInstalledPackages -ErrorAction Stop|Where-Object {$_.IsInstalled -and $_.PackageID -eq $State.PackageId -and $_.Version -eq $State.PackageVersion -and $_.PackageName -eq 'windows_setup_hide_oobe'})
 if($installed.Count -eq 1){$State.Phase='AwaitingLogon';Save-InitProvisioningState $State $StatePath;return}
 $State.Phase='ApplyPending';Save-InitProvisioningState $State $StatePath
 Write-Host '下一步會完成初始設定；Windows 可能立即重新啟動。請先保存其他工作。' -ForegroundColor Yellow
 if($null -eq $Confirm -or (& $Confirm) -ne $true){$State.Phase='AwaitingConsent';Save-InitProvisioningState $State $StatePath;Write-Host '已取消套用；帳號與無密碼續跑紀錄保留。';return}
 Install-ProvisioningPackage -PackagePath (Join-Path $AssetRoot 'hide_oobe.ppkg') -QuietInstall -ErrorAction Stop|Out-Null
 $installed=@(Get-ProvisioningPackage -AllInstalledPackages -ErrorAction Stop|Where-Object {$_.IsInstalled -and $_.PackageID -eq $State.PackageId -and $_.Version -eq $State.PackageVersion -and $_.PackageName -eq 'windows_setup_hide_oobe'})
 if($installed.Count -ne 1){throw '尚未確認設定包完成；保留 Pending，請重新執行以讀回狀態。'}
 $State.Phase='AwaitingLogon';$State.LastErrorCode='';Save-InitProvisioningState $State $StatePath
}
function New-InitProvisioningStage {
 param([string]$SourceRoot,[string]$StageRoot,$InitialState)
 Assert-InitPlainPath $SourceRoot;Assert-InitPlainPath $StageRoot
 $null=Assert-InitProvisioningAsset -AssetRoot (Join-Path $SourceRoot 'modules/init/assets')
 if(Test-Path -LiteralPath $StageRoot){throw '已有 Init 續跑目錄，請從其 resume_init.cmd 繼續，不能覆寫。'}
 $files=@('modules/init/initialize_nuc.ps1','modules/init/init_entry_library.ps1','modules/init/oobe_library.ps1','modules/init/provisioning_library.ps1','modules/init/provisioning_asset_library.ps1','modules/init/provisioning_launcher_library.ps1','modules/init/assets/hide_oobe.xml','modules/init/assets/hide_oobe.ppkg','modules/init/assets/provenance.json')
 foreach($relative in $files){$path=Join-Path $SourceRoot $relative;Assert-InitPlainPath $path;if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw ('缺少 Init 依賴：'+$relative)}}
 if($null -eq $InitialState){throw '暫存前必須提供無帳密的初始狀態。'}
 $finalRoot=$StageRoot
 $StageRoot=$finalRoot+'.preparing.'+[guid]::NewGuid().ToString('N')
 New-Item -ItemType Directory -Path $StageRoot -ErrorAction Stop|Out-Null
 try{
 Protect-InitFolder $StageRoot;Assert-InitProtectedDirectory $StageRoot
 foreach($relative in $files){
  $target=Join-Path (Join-Path $StageRoot 'runtime') $relative
  New-Item -ItemType Directory -Path (Split-Path $target -Parent) -Force|Out-Null
  Copy-Item -LiteralPath (Join-Path $SourceRoot $relative) -Destination $target -ErrorAction Stop
  if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath (Join-Path $SourceRoot $relative) -Algorithm SHA256).Hash){throw ('暫存依賴雜湊不符：'+$relative)}
 }
 $command='@echo off'+"`r`n"+'powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0runtime\modules\init\initialize_nuc.ps1" -ResumeStatePath "%~dp0state.json"'+"`r`n"
 [IO.File]::WriteAllText((Join-Path $StageRoot 'resume_init.cmd'),$command,[Text.Encoding]::ASCII)
 Save-InitProvisioningState $InitialState (Join-Path $StageRoot 'state.json')
 [IO.Directory]::Move($StageRoot,$finalRoot)
 }catch{Write-Warning ('Init 暫存未完成；診斷目錄保留於 '+$StageRoot+'。正式續跑位置未建立，可重新執行來源入口。');throw}
}
function Test-InitSecurePasswordPair {
 param([Security.SecureString]$Password,[Security.SecureString]$Confirmation)
 if($null -eq $Password -or $null -eq $Confirmation -or $Password.Length -lt 1 -or $Password.Length -gt 127 -or $Password.Length -ne $Confirmation.Length){return $false}
 $one=[IntPtr]::Zero;$two=[IntPtr]::Zero
 try{
  $one=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password);$two=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($Confirmation)
  for($i=0;$i -lt $Password.Length;$i++){
   $value=[Runtime.InteropServices.Marshal]::ReadInt16($one,$i*2)
   if($value -ge 0 -and $value -lt 32){return $false}
   if($value -ne [Runtime.InteropServices.Marshal]::ReadInt16($two,$i*2)){return $false}
  }
  return $true
 }finally{if($one -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($one)};if($two -ne [IntPtr]::Zero){[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($two)}}
}
function Read-InitProvisioningState {
 param([string]$StatePath,[string]$MachineGuid,[string]$PackageHash)
 Assert-InitProtectedDirectory (Split-Path $StatePath -Parent)
 Assert-InitProtectedFile $StatePath
 $state=[IO.File]::ReadAllText($StatePath)|ConvertFrom-Json
 Assert-InitProvisioningState $state $MachineGuid $PackageHash
 return $state
}
function Invoke-InitOobeFlow {
 param([string]$SourceRoot,[string]$StageRoot)
 $context=Get-InitProvisioningContext
 if(-not(Test-InitProvisioningContext -Sid $context.Sid -Build $context.Build -ProductType $context.ProductType -Is64Bit $context.Is64Bit -IsWinPE $context.IsWinPE -OobeApiSucceeded $context.OobeApiSucceeded -OobeComplete $context.OobeComplete)){throw '目前不是可確認的 Windows 11 22H2 以上初始設定環境；未建立帳號或套用設定。'}
 $asset=Assert-InitProvisioningAsset -AssetRoot (Join-Path $SourceRoot 'modules/init/assets')
 $statePath=Join-Path $StageRoot 'state.json'
 if(Test-Path -LiteralPath $StageRoot){
  $state=Read-InitProvisioningState $statePath $context.MachineGuid $asset.PackageSHA256
 }else{
  $state=New-InitProvisioningState $context.MachineGuid $context.ComputerName $SourceRoot $asset.PackageSHA256
  New-InitProvisioningStage $SourceRoot $StageRoot $state
 }
 $launcher=New-InitPublicLauncher -StageRoot $StageRoot
 Write-Host ('取消或中斷時的恢復入口（正常登入後直接執行 windows.cmd）：'+$launcher) -ForegroundColor Cyan
 if($state.Phase -eq 'Prepared'){
  $name=Read-Host '新的本機管理員帳號'
  if(-not(Test-InitUserName -Name $name -ExistingNames @((Get-LocalUser).Name))){throw '帳號無效或已存在；不變更既有帳號。'}
  $password=$null;$confirmation=$null
  try{
   $password=Read-Host '新帳號密碼' -AsSecureString;$confirmation=Read-Host '再次輸入密碼' -AsSecureString
   if(-not(Test-InitSecurePasswordPair $password $confirmation)){throw '兩次密碼不同、為空或含不允許字元。'}
   New-InitProvisioningAccount $state $name $password $statePath
  }finally{if($password){$password.Dispose()};if($confirmation){$confirmation.Dispose()}}
 }elseif($state.Phase -eq 'AccountCreated'){
  New-InitProvisioningAccount $state $state.TargetUserName $null $statePath
 }
 Invoke-InitProvisioningApply $state $statePath (Join-Path $StageRoot 'runtime/modules/init/assets') { (Read-Host '是否現在繼續？Windows 可能重新啟動；同意請輸入 YES') -ceq 'YES' }
 if($state.Phase -eq 'AwaitingLogon'){Write-Host '請依 Windows 畫面登入剛建立的正式帳號，直接執行 windows.cmd；SSH 由 Windows 第 4 階段處理，不需再跑 Init。'}
}
function Get-InitIdentityContext {
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 $principal=New-Object Security.Principal.WindowsPrincipal($identity)
 return @{Sid=$identity.User.Value;IsAdministrator=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator);SessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId}
}
function Get-InitProvisioningContext {
 $identity=Get-InitIdentityContext
 $os=Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
 $setup=Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\Setup' -ErrorAction Stop
 $image=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State' -ErrorAction Stop
 $machine=Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -ErrorAction Stop
 $processes=@(Get-CimInstance -ClassName Win32_Process -Filter "Name='msoobe.exe' OR Name='CloudExperienceHostBroker.exe' OR Name='CloudExperienceHostApp.exe' OR Name='oobenetworkconnectionflow.exe' OR Name='explorer.exe'" -ErrorAction Stop)
 $session=@($processes|Where-Object {$_.SessionId -eq $identity.SessionId})
 $oobe=@($session|Where-Object {$_.Name -in @('msoobe.exe','CloudExperienceHostBroker.exe','CloudExperienceHostApp.exe','oobenetworkconnectionflow.exe')}).Count -gt 0
 $desktop=$false;$registered=''
 if($identity.Sid -ne 'S-1-5-18'){
  $profile=Get-ItemProperty -LiteralPath ('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\'+$identity.Sid) -ErrorAction Stop
  $registered=[Environment]::ExpandEnvironmentVariables([string]$profile.ProfileImagePath)
  foreach($process in @($session|Where-Object {$_.Name -eq 'explorer.exe'})){if((Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid -ErrorAction Stop).Sid -eq $identity.Sid){$desktop=$true}}
 }
 $completion=Invoke-InitOobeCompleteNative
 return @{Sid=$identity.Sid;IsAdministrator=$identity.IsAdministrator;Build=[int]$os.BuildNumber;ProductType=[int]$os.ProductType;Is64Bit=([Environment]::Is64BitProcess -and $env:PROCESSOR_ARCHITECTURE -eq 'AMD64');IsWinPE=[bool](Test-Path -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\MiniNT');OobeInProgress=[int]$setup.OOBEInProgress;SetupInProgress=[int]$setup.SystemSetupInProgress;OobeProcessInSession=$oobe;OobeApiSucceeded=[bool]$completion.Succeeded;OobeComplete=[bool]$completion.Complete;MachineGuid=[string]$machine.MachineGuid;ComputerName=$env:COMPUTERNAME;ImageState=[string]$image.ImageState;DesktopOwned=$desktop;ProfilePath=$env:USERPROFILE;RegisteredProfile=$registered}
}
function Invoke-InitOobeCompleteNative {
 if(-not ('WindowsSetup.InitOobeNative' -as [type])){
  Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
namespace WindowsSetup { public static class InitOobeNative {
 [DllImport("kernel32.dll", SetLastError=true)]
 [return: MarshalAs(UnmanagedType.Bool)]
 public static extern bool OOBEComplete([MarshalAs(UnmanagedType.Bool)] out bool complete);
} }
'@
 }
 $complete=$false
 $success=[WindowsSetup.InitOobeNative]::OOBEComplete([ref]$complete)
 return [pscustomobject]@{Succeeded=$success;Complete=$complete;ErrorCode=$(if($success){0}else{[Runtime.InteropServices.Marshal]::GetLastWin32Error()})}
}
function Invoke-InitProvisioningEntry {
 param([string]$SourceRoot,[string]$StageRoot,[string]$ResumeStatePath,[string]$ExpectedUserSID)
 $context=Get-InitProvisioningContext
 if($ExpectedUserSID -and $ExpectedUserSID -ne $context.Sid){throw '提權後帳號已改變，請使用原帳號的管理員權限。'}
 $statePath=Join-Path $StageRoot 'state.json'
 if($ResumeStatePath -and [IO.Path]::GetFullPath($ResumeStatePath) -ine [IO.Path]::GetFullPath($statePath)){throw '續跑狀態位置不符，拒絕載入。'}
 if($context.Sid -eq 'S-1-5-18'){
  $runtime=if(Test-Path -LiteralPath $statePath){Join-Path $StageRoot 'runtime'}else{$SourceRoot}
  Invoke-InitOobeFlow -SourceRoot $runtime -StageRoot $StageRoot
  return $true
 }
 if(-not $context.IsAdministrator){
  if($ResumeStatePath){throw '請從公開 windows_setup_init.cmd 續跑並允許原帳號管理員權限。'}
  return $false
 }
 if(-not $ResumeStatePath -and -not(Test-Path -LiteralPath $statePath)){return $false}
 Assert-InitProtectedDirectory $StageRoot
 $asset=Assert-InitProvisioningAsset -AssetRoot (Join-Path $StageRoot 'runtime/modules/init/assets')
 $state=Read-InitProvisioningState $statePath $context.MachineGuid $asset.PackageSHA256
 if($context.Sid -ne $state.TargetSid){throw '目前帳號不是本輪建立的目標 SID，停止續跑。'}
 Confirm-InitAccountCheckpoint $state $statePath $context $asset.PackageSHA256
 return $true
}
function Invoke-InitWindowsCheckpoint {
 param([string]$StageRoot)
 $context=Get-InitProvisioningContext
 if(-not $context.IsAdministrator -or $context.Sid -eq 'S-1-5-18'){throw 'Windows 帳號確認需正式使用者的管理員權限。'}
 if(-not(Test-Path -LiteralPath $StageRoot)){return $false}
 Assert-InitProtectedDirectory $StageRoot
 $statePath=Join-Path $StageRoot 'state.json'
 if(-not(Test-Path -LiteralPath $statePath -PathType Leaf)){throw '已有 Init 暫存但缺少狀態，停止以免略過未完成初始化。'}
 $asset=Assert-InitProvisioningAsset -AssetRoot (Join-Path $StageRoot 'runtime/modules/init/assets')
 $state=Read-InitProvisioningState $statePath $context.MachineGuid $asset.PackageSHA256
 Confirm-InitAccountCheckpoint $state $statePath $context $asset.PackageSHA256
 return $true
}
