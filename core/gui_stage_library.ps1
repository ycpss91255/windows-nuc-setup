#Requires -Version 5.1
# Definitions only. No directories, ACLs or tasks are changed when this file is loaded.
function Assert-SetupGuiPlainPath {
 param([Parameter(Mandatory=$true)][string]$Path)
 $cursor=[IO.Path]::GetFullPath($Path)
 if($cursor -notmatch '^[a-zA-Z]:\\'){throw 'GUI workerstage必須使用本機絕對磁碟路徑。'}
 while($cursor){
  if(Test-Path -LiteralPath $cursor){$item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop;if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw ('GUI worker來源不接受重新解析點：'+$cursor)}}
  $parent=[IO.Path]::GetDirectoryName($cursor);if($parent -eq $cursor){break};$cursor=$parent
 }
}
function New-SetupGuiDirectorySecurity {
 param([string]$UserSid)
 $acl=New-Object Security.AccessControl.DirectorySecurity
 $acl.SetAccessRuleProtection($true,$false)
 $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
 foreach($id in @('S-1-5-18','S-1-5-32-544')){$sid=New-Object Security.Principal.SecurityIdentifier($id);$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')))}
 if($UserSid){$sid=New-Object Security.Principal.SecurityIdentifier($UserSid);$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid,'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow')))}
 return $acl
}
function Assert-SetupGuiAcl {
 param([Parameter(Mandatory=$true)]$Acl,[switch]$Directory,[switch]$Ancestor,[string]$UserSid)
 $trusted=@('S-1-5-18','S-1-5-32-544')
 $owners=@($trusted)
 if($Ancestor){try{$owners+=@((New-Object Security.Principal.NTAccount('NT SERVICE','TrustedInstaller')).Translate([Security.Principal.SecurityIdentifier]).Value)}catch{}}
 $owner=$Acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
 if($owner -notin $owners){throw 'GUI worker路徑擁有者不可信，保留原資料並拒絕接管。'}
 $rules=@($Acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
 if($Ancestor){
  $danger=[Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership
  foreach($rule in $rules){
   if($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin $owners -and -not($rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) -and ($rule.FileSystemRights -band $danger)){throw 'GUI worker父目錄允許非可信身分刪除或替換子目錄，拒絕使用。'}
  }
  return
 }
 if($Directory -and -not $Acl.AreAccessRulesProtected){throw 'GUI worker目錄ACL未停用繼承。'}
 if($Directory -and $UserSid -and $owner -cne 'S-1-5-32-544'){throw 'GUI worker data目錄擁有者必須是管理員群組。'}
 $readOnly=[Security.AccessControl.FileSystemRights]::ReadAndExecute -bor [Security.AccessControl.FileSystemRights]::Synchronize
 foreach($rule in $rules){
  if($rule.AccessControlType -ne 'Allow'){throw 'GUI worker來源ACL含非預期存取規則。'}
  if($rule.IdentityReference.Value -in $trusted){continue}
  if(-not $UserSid -or $rule.IdentityReference.Value -cne $UserSid -or ($rule.FileSystemRights -band (-bnot $readOnly)) -ne 0){throw 'GUI worker來源ACL含非預期存取規則。'}
 }
 if($UserSid -and -not @($rules|Where-Object {$_.IdentityReference.Value -ceq $UserSid -and ($_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::ReadAndExecute) -eq [Security.AccessControl.FileSystemRights]::ReadAndExecute -and -not($_.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly)}).Count){throw 'GUI worker data ACL缺少原使用者讀取權限。'}
 foreach($sid in $trusted){
  $matches=@($rules|Where-Object {$_.IdentityReference.Value -eq $sid -and ($_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -eq [Security.AccessControl.FileSystemRights]::FullControl -and -not($_.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly)})
  if(-not $matches.Count){throw 'GUI worker來源ACL缺少SYSTEM或管理員完整權限。'}
  if($Directory -and -not @($matches|Where-Object {$_.InheritanceFlags -eq ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit) -and $_.PropagationFlags -eq [Security.AccessControl.PropagationFlags]::None}).Count){throw 'GUI worker目錄ACL缺少子檔繼承保護。'}
 }
}
function Assert-SetupGuiProtectedPath {
 param([Parameter(Mandatory=$true)][string]$Path,[switch]$Directory,[string]$UserSid)
 Assert-SetupGuiPlainPath $Path
 $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
 if([bool]$item.PSIsContainer -ne [bool]$Directory){throw 'GUI workerstage檔案或目錄類型不符。'}
 Assert-SetupGuiAcl -Acl (Get-Acl -LiteralPath $Path -ErrorAction Stop) -Directory:$Directory -UserSid $UserSid
}
function Assert-SetupGuiAncestors {
 param([Parameter(Mandatory=$true)][string]$CommonDataRoot)
 Assert-SetupGuiPlainPath $CommonDataRoot
 $cursor=[IO.Path]::GetFullPath($CommonDataRoot)
 while($cursor){
  $item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
  if(-not $item.PSIsContainer){throw 'GUI worker父路徑不是目錄。'}
  Assert-SetupGuiAcl -Acl (Get-Acl -LiteralPath $cursor -ErrorAction Stop) -Ancestor
  $parent=[IO.Path]::GetDirectoryName($cursor);if($parent -eq $cursor){break};$cursor=$parent
 }
}
function New-SetupGuiProtectedDirectory {
 param([Parameter(Mandatory=$true)][string]$Path,[string]$UserSid)
 Assert-SetupGuiPlainPath $Path
 if(-not(Test-Path -LiteralPath $Path)){
  $acl=New-SetupGuiDirectorySecurity -UserSid $UserSid
  # The security descriptor is supplied at creation; there is no create-then-protect interval.
  [void][IO.Directory]::CreateDirectory($Path,$acl)
 }
 Assert-SetupGuiProtectedPath -Path $Path -Directory -UserSid $UserSid
}
function Get-SetupGuiStageFiles {
 param([string]$Role)
 if($Role -cne 'Explorer'){throw 'GUI worker角色尚未核准。'}
 return @('core/gui_stage_library.ps1','core/gui_worker.ps1','modules/explorer/explorer_settings_library.ps1','modules/explorer/native/explorer.cs')
}
function Get-SetupGuiRunPaths {
 param([string]$CommonDataRoot,[string]$Role,[string]$RunId)
 $null=Get-SetupGuiStageFiles $Role
 $guid=[guid]::Empty
 if(-not [guid]::TryParse($RunId,[ref]$guid) -or $guid.ToString('D') -cne $RunId){throw 'GUI worker本輪ID格式不符。'}
 $roleRoot=Join-Path (Join-Path ([IO.Path]::GetFullPath($CommonDataRoot)) 'windows_setup_gui') $Role.ToLowerInvariant()
 $runRoot=Join-Path $roleRoot $RunId
 [pscustomobject]@{RoleRoot=$roleRoot;RunRoot=$runRoot;CodeRoot=(Join-Path $runRoot 'code');DataRoot=(Join-Path $runRoot 'data')}
}
function Assert-SetupGuiCaller {
 param([string]$UserSid,[int]$CallerSession,[int]$DesktopSession,[string]$Computer)
 if($UserSid -notmatch '^S-1-(5-21|12-1)-\d+(-\d+)+$' -or [string]::IsNullOrWhiteSpace($Computer)){throw 'GUI worker呼叫身分格式不符。'}
 if($CallerSession -lt 0 -or $DesktopSession -le 0 -or ($CallerSession -gt 0 -and $CallerSession -ne $DesktopSession)){throw 'GUI worker必須對應同一使用者的唯一互動桌面。'}
}
function Write-SetupGuiAtomicJson {
 param([string]$Path,$Value,[string]$UserSid)
 $parent=Split-Path $Path -Parent
 Assert-SetupGuiProtectedPath $parent -Directory -UserSid $UserSid
 if(Test-Path -LiteralPath $Path){Assert-SetupGuiProtectedPath $Path -UserSid $UserSid}
 $temporary=Join-Path $parent ([guid]::NewGuid().ToString('N')+'.tmp')
 [IO.File]::WriteAllText($temporary,($Value|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($true))
 Assert-SetupGuiProtectedPath $temporary -UserSid $UserSid
 if(Test-Path -LiteralPath $Path){[IO.File]::Replace($temporary,$Path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temporary,$Path)}
}
function New-SetupGuiStage {
 param([Parameter(Mandatory=$true)][string]$SourceRoot,[Parameter(Mandatory=$true)][string]$CommonDataRoot,
 [string]$Role,[string]$UserSid,[int]$CallerSession,[int]$DesktopSession,[string]$Computer,[switch]$VerifyOnly)
 $ErrorActionPreference='Stop'
 $manifest=@(Get-SetupGuiStageFiles $Role)
 Assert-SetupGuiCaller -UserSid $UserSid -CallerSession $CallerSession -DesktopSession $DesktopSession -Computer $Computer
 Assert-SetupGuiAncestors $CommonDataRoot
 $paths=Get-SetupGuiRunPaths -CommonDataRoot $CommonDataRoot -Role $Role -RunId ([guid]::NewGuid().ToString('D'))
 New-SetupGuiProtectedDirectory (Split-Path $paths.RoleRoot -Parent)
 New-SetupGuiProtectedDirectory $paths.RoleRoot
 $lockPath=Join-Path $paths.RoleRoot 'stage.lock'
 if(Test-Path -LiteralPath $lockPath){Assert-SetupGuiProtectedPath $lockPath}
 try{$lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{throw 'GUI stage已被另一個程序使用，未複製或啟動工作。'}
 try{
  Assert-SetupGuiProtectedPath $lockPath
  Assert-SetupGuiAncestors $CommonDataRoot
  foreach($path in @($paths.RunRoot,$paths.CodeRoot)){New-SetupGuiProtectedDirectory $path}
  New-SetupGuiProtectedDirectory $paths.DataRoot -UserSid $UserSid
  $files=@()
  foreach($name in $manifest){
   $source=Join-Path $SourceRoot $name;Assert-SetupGuiPlainPath $source
   if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw ('GUI worker來源缺少檔案：'+$name)}
   $expected=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
   $parent=$paths.CodeRoot
   foreach($part in @($name.Split('/')[0..($name.Split('/').Length-2)])){$parent=Join-Path $parent $part;New-SetupGuiProtectedDirectory $parent}
   $target=Join-Path $paths.CodeRoot $name;Assert-SetupGuiPlainPath $target
   if(Test-Path -LiteralPath $target){throw 'GUI worker全新stage已有非預期檔案，拒絕覆寫。'}
   Copy-Item -LiteralPath $source -Destination $target -ErrorAction Stop
   Assert-SetupGuiProtectedPath $target
   if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -cne $expected -or (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -cne $expected){throw 'GUI worker來源複製前後雜湊不符。'}
   $files+=@([pscustomobject]@{Name=$name;SHA256=$expected.ToLowerInvariant()})
  }
  $context=[pscustomobject][ordered]@{Schema=1;Role=$Role;RunId=(Split-Path $paths.RunRoot -Leaf);Computer=$Computer;CallerSID=$UserSid;CallerSession=$CallerSession;UserSID=$UserSid;DesktopSession=$DesktopSession;VerifyOnly=[bool]$VerifyOnly;Files=$files}
  Write-SetupGuiAtomicJson -Path (Join-Path $paths.CodeRoot 'context.json') -Value $context
  $verified=Read-SetupGuiContext -CodeRoot $paths.CodeRoot -CommonDataRoot $CommonDataRoot -Role $Role -RunId $context.RunId
  [pscustomobject]@{CodeRoot=$paths.CodeRoot;DataRoot=$paths.DataRoot;CommonDataRoot=$CommonDataRoot;Lock=$lock;Context=$verified}
 }catch{$lock.Dispose();throw}
}
function Read-SetupGuiContext {
 param([string]$CodeRoot,[string]$CommonDataRoot,[string]$Role,[string]$RunId)
 $paths=Get-SetupGuiRunPaths -CommonDataRoot $CommonDataRoot -Role $Role -RunId $RunId
 if([IO.Path]::GetFullPath($CodeRoot) -ine $paths.CodeRoot){throw 'GUI worker必須使用固定角色與本輪code目錄。'}
 Assert-SetupGuiAncestors $CommonDataRoot
 Assert-SetupGuiProtectedPath (Split-Path $paths.RoleRoot -Parent) -Directory
 Assert-SetupGuiProtectedPath $paths.RoleRoot -Directory
 Assert-SetupGuiProtectedPath $paths.RunRoot -Directory
 Assert-SetupGuiProtectedPath $CodeRoot -Directory
 $path=Join-Path $CodeRoot 'context.json';Assert-SetupGuiProtectedPath $path
 $context=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
 if($context.Schema -ne 1 -or $context.Role -cne $Role -or $context.RunId -cne $RunId -or $context.CallerSID -cne $context.UserSID -or $context.VerifyOnly -isnot [bool] -or $context.CallerSession -isnot [int] -or $context.DesktopSession -isnot [int]){throw 'GUI worker context身分或格式不符。'}
 Assert-SetupGuiCaller -UserSid $context.UserSID -CallerSession $context.CallerSession -DesktopSession $context.DesktopSession -Computer $context.Computer
 $expected=@(Get-SetupGuiStageFiles $Role|Sort-Object)
 if(@($context.Files).Count -ne $expected.Count -or (@($context.Files|ForEach-Object Name|Sort-Object) -join '|') -cne ($expected -join '|')){throw 'GUI worker context來源清單不符。'}
 foreach($file in $context.Files){
  if($file.SHA256 -cnotmatch '^[a-f0-9]{64}$'){throw 'GUI worker context雜湊格式不符。'}
  $target=Join-Path $CodeRoot $file.Name;Assert-SetupGuiProtectedPath $target
  if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.SHA256){throw ('GUI worker stage來源雜湊不符：'+$file.Name)}
 }
 Assert-SetupGuiProtectedPath $paths.DataRoot -Directory -UserSid $context.UserSID
 return $context
}
function Assert-SetupGuiWorkerScope {
 param($Context,$Scope)
 if($Scope.UserSID -cne $Context.UserSID -or $Scope.Computer -cne $Context.Computer -or $Scope.SessionId -ne $Context.DesktopSession -or $Scope.SessionId -le 0){throw 'GUI worker實際執行身分或桌面不符，未套用任何設定。'}
}
function Get-SetupGuiResultName {
 param($Context)
 $null=Get-SetupGuiStageFiles $Context.Role
 if($Context.VerifyOnly){return 'Explorer-Verification.json'}
 return 'Explorer-Result.json'
}
function Write-SetupGuiResult {
 param([string]$DataRoot,$Context,[Collections.IDictionary]$Result)
 $envelope=[ordered]@{Schema=1;Role=$Context.Role;RunId=$Context.RunId;UserSID=$Context.UserSID;SessionId=$Context.DesktopSession;Computer=$Context.Computer;VerifyOnly=$Context.VerifyOnly}
 foreach($name in $Result.Keys){if($envelope.Contains($name)){throw 'GUI worker結果不可覆寫本輪身分。'};$envelope[$name]=$Result[$name]}
 Write-SetupGuiAtomicJson -Path (Join-Path $DataRoot (Get-SetupGuiResultName $Context)) -Value $envelope -UserSid $Context.UserSID
}
function Read-SetupGuiResult {
 param($Stage)
 $context=Read-SetupGuiContext -CodeRoot $Stage.CodeRoot -CommonDataRoot $Stage.CommonDataRoot -Role $Stage.Context.Role -RunId $Stage.Context.RunId
 if(($context|ConvertTo-Json -Depth 8 -Compress) -cne ($Stage.Context|ConvertTo-Json -Depth 8 -Compress)){throw 'GUI worker context在本輪執行期間改變。'}
 $paths=Get-SetupGuiRunPaths -CommonDataRoot $Stage.CommonDataRoot -Role $context.Role -RunId $context.RunId
 if([IO.Path]::GetFullPath($Stage.DataRoot) -ine $paths.DataRoot){throw 'GUI worker結果必須使用本輪固定data目錄。'}
 $path=Join-Path $paths.DataRoot (Get-SetupGuiResultName $context);Assert-SetupGuiProtectedPath $path -UserSid $context.UserSID
 $result=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
 if($result.Schema -ne 1 -or $result.Role -cne $context.Role -or $result.RunId -cne $context.RunId -or $result.UserSID -cne $context.UserSID -or $result.Computer -cne $context.Computer -or $result.SessionId -ne $context.DesktopSession -or $result.VerifyOnly -isnot [bool] -or $result.VerifyOnly -ne $context.VerifyOnly -or $result.Success -isnot [bool]){throw 'GUI worker結果身分或本輪ID不符。'}
 return $result
}
function Get-SetupGuiIdentity {
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 [pscustomobject]@{UserSID=$identity.User.Value;Computer=[Environment]::MachineName;SessionId=[Diagnostics.Process]::GetCurrentProcess().SessionId;CommonDataRoot=[Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData);PowerShell=(Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::System)) 'WindowsPowerShell/v1.0/powershell.exe')}
}
function Get-SetupGuiDesktopSession {
 param($Scope)
 $matching=@(foreach($process in @(Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop)){
  if($process.SessionId -le 0 -or ($Scope.SessionId -gt 0 -and $Scope.SessionId -ne $process.SessionId)){continue}
  $owner=Invoke-CimMethod -InputObject $process -MethodName GetOwnerSid -ErrorAction Stop
  if($owner.ReturnValue -eq 0 -and $owner.Sid -ceq $Scope.UserSID){[int]$process.SessionId}
 })
 $sessions=@($matching|Select-Object -Unique)
 if($sessions.Count -ne 1){throw 'GUI worker找不到同一使用者唯一的互動桌面，未啟動工作。'}
 return $sessions[0]
}
function Invoke-SetupGuiLocalWorker {
 param($Stage,$Scope)
 $null= & (Join-Path $Stage.CodeRoot 'core/gui_worker.ps1') -Role $Stage.Context.Role -RunId $Stage.Context.RunId
}
function Invoke-SetupGuiScheduledWorker {
 param($Stage,$Scope)
 $context=$Stage.Context;$worker=Join-Path $Stage.CodeRoot 'core/gui_worker.ps1'
 Assert-SetupGuiProtectedPath $worker
 $name='WindowsSetup-Gui-'+$context.Role+'-'+$context.RunId
 if(Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue){throw 'GUI worker本輪排程名稱已存在，拒絕接管。'}
 $arguments='-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$worker+'" -Role '+$context.Role+' -RunId '+$context.RunId
 $action=New-ScheduledTaskAction -Execute $Scope.PowerShell -Argument $arguments
 $principal=New-ScheduledTaskPrincipal -UserId $context.UserSID -LogonType Interactive -RunLevel Highest
 $registered=$false
 try{
  Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -ErrorAction Stop|Out-Null
  $registered=$true;Start-ScheduledTask -TaskName $name -ErrorAction Stop
  $resultPath=Join-Path $Stage.DataRoot (Get-SetupGuiResultName $context);$deadline=(Get-Date).AddSeconds(60)
  do{
   Start-Sleep -Seconds 2;$task=Get-ScheduledTask -TaskName $name -ErrorAction Stop
   if((Test-Path -LiteralPath $resultPath) -and $task -and $task.State -ne 'Running'){
    $info=Get-ScheduledTaskInfo -TaskName $name -ErrorAction Stop
    if($null -eq $info -or $info.LastTaskResult -ne 0){throw ('GUI worker排程退出碼不是0：'+[string]$info.LastTaskResult)}
    return
   }
  }while((Get-Date) -lt $deadline)
  throw '尚未取得受保護的本輪GUI worker結果；請確認原帳號已登入桌面。'
 }finally{
  if($registered){$task=Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue;if($task -and $task.State -ne 'Running'){Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction Stop}}
 }
}
function Invoke-SetupGuiRole {
 param([Parameter(Mandatory=$true)][string]$PackageRoot,[string]$Role,[switch]$Worker,[switch]$VerifyOnly)
 $ErrorActionPreference='Stop'
 $null=Get-SetupGuiStageFiles $Role
 $scope=Get-SetupGuiIdentity
 if($Worker -and $scope.SessionId -eq 0){throw 'GUI -Worker不能在session 0繞過原使用者桌面身分。'}
 $desktop=Get-SetupGuiDesktopSession $scope
 $stage=New-SetupGuiStage -SourceRoot $PackageRoot -CommonDataRoot $scope.CommonDataRoot -Role $Role -UserSid $scope.UserSID -CallerSession $scope.SessionId -DesktopSession $desktop -Computer $scope.Computer -VerifyOnly:$VerifyOnly
 try{
  $context=Read-SetupGuiContext -CodeRoot $stage.CodeRoot -CommonDataRoot $stage.CommonDataRoot -Role $Role -RunId $stage.Context.RunId
  if(($context|ConvertTo-Json -Depth 8 -Compress) -cne ($stage.Context|ConvertTo-Json -Depth 8 -Compress)){throw 'GUI worker啟動前context已改變。'}
  if($scope.SessionId -eq 0){Invoke-SetupGuiScheduledWorker -Stage $stage -Scope $scope}else{Invoke-SetupGuiLocalWorker -Stage $stage -Scope $scope}
  $result=Read-SetupGuiResult -Stage $stage
  if(-not $result.Success){throw $result.Error}
  return $result
 }finally{$stage.Lock.Dispose()}
}
function Open-SetupGuiExecutionLock {
 param($Paths)
 Assert-SetupGuiProtectedPath $Paths.RoleRoot -Directory
 $path=Join-Path $Paths.RoleRoot 'execution.lock'
 if(Test-Path -LiteralPath $path){Assert-SetupGuiProtectedPath $path}
 try{$lease=[IO.File]::Open($path,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{throw 'GUI worker角色已有執行程序，未執行任何UI設定。'}
 try{Assert-SetupGuiProtectedPath $path;return $lease}catch{$lease.Dispose();throw}
}
function Invoke-SetupGuiWorker {
 param([Parameter(Mandatory=$true)][string]$CodeRoot,[string]$Role,[string]$RunId)
 $ErrorActionPreference='Stop'
 $scope=Get-SetupGuiIdentity
 $context=Read-SetupGuiContext -CodeRoot $CodeRoot -CommonDataRoot $scope.CommonDataRoot -Role $Role -RunId $RunId
 Assert-SetupGuiWorkerScope -Context $context -Scope $scope
 $paths=Get-SetupGuiRunPaths -CommonDataRoot $scope.CommonDataRoot -Role $Role -RunId $RunId
 $lease=$null;$published=$false
 try{
  $lease=Open-SetupGuiExecutionLock -Paths $paths
  # Role and all executable file hashes were validated before importing this fixed library.
  $module=Join-Path $CodeRoot 'modules/explorer'
  . (Join-Path $module 'explorer_settings_library.ps1')
  $result=Invoke-SetupExplorerSettings -ModuleRoot $module -VerifyOnly:$context.VerifyOnly
  if($result.Success -isnot [bool]){throw 'GUI worker葉節點未提供有效成功狀態。'}
  $details=[ordered]@{};foreach($property in $result.PSObject.Properties){$details[$property.Name]=$property.Value}
  Write-SetupGuiResult -DataRoot $paths.DataRoot -Context $context -Result $details
  $published=$true
  if(-not $result.Success){throw $result.Error}
  return $result
 }catch{
  if(-not $published){Write-SetupGuiResult -DataRoot $paths.DataRoot -Context $context -Result @{Success=$false;Error=$_.Exception.Message;FailedAt=(Get-Date).ToString('o')}}
  throw
 }finally{if($lease){$lease.Dispose()}}
}
