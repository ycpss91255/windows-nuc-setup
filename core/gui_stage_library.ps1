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
function Assert-SetupIconReference {
 param($Reference)
 if($null -eq $Reference -or $Reference.Width -isnot [int] -or $Reference.Height -isnot [int] -or $Reference.Width -le 0 -or $Reference.Height -le 0 -or @($Reference.Icons).Count -ne 4){throw '圖示範本必須包含有效尺寸與四個唯一圖示。'}
 $names=@()
 foreach($icon in $Reference.Icons){if($icon.Name -isnot [string] -or [string]::IsNullOrWhiteSpace($icon.Name) -or $icon.X -isnot [int] -or $icon.Y -isnot [int]){throw '圖示範本名稱或座標格式不符。'};$names+=@($icon.Name)}
 if(@($names|Select-Object -Unique).Count -ne 4){throw '圖示範本名稱必須唯一。'}
}
function Write-SetupIconReference {
 param([Parameter(Mandatory=$true)][string]$PackageRoot,$Reference)
 Assert-SetupIconReference $Reference
 $path=Join-Path ([IO.Path]::GetFullPath($PackageRoot)) 'modules/desktop/desktop_layout.json'
 Assert-SetupGuiPlainPath $path
 $temporary=Join-Path (Split-Path $path -Parent) ([guid]::NewGuid().ToString('N')+'.tmp')
 try{
  [IO.File]::WriteAllText($temporary,($Reference|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($true))
  Assert-SetupGuiPlainPath $path
  if(Test-Path -LiteralPath $path){[IO.File]::Replace($temporary,$path,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temporary,$path)}
 }finally{if(Test-Path -LiteralPath $temporary){[IO.File]::Delete($temporary)}}
}
function Get-SetupGuiStageFiles {
 param([string]$Role)
 if($Role -ceq 'Start'){return @('core/gui_stage_library.ps1','core/gui_worker.ps1','modules/start_menu/start_menu_settings_library.ps1','modules/start_menu/start_pins_policy_library.ps1','modules/start_menu/start_pins_asset_library.ps1','modules/start_menu/assets/empty_start.xml','modules/start_menu/assets/empty_start.ppkg','modules/start_menu/assets/provenance.json')}
 if($Role -ceq 'Desktop'){return @('core/gui_stage_library.ps1','core/gui_worker.ps1','modules/desktop/desktop_settings_library.ps1','modules/desktop/desktop_safety.ps1')}
 if($Role -ceq 'Icons'){return @('core/gui_stage_library.ps1','core/gui_worker.ps1','modules/desktop/icons_settings_library.ps1','modules/desktop/native/desktop_icons.cs')}
 if($Role -cnotin @('Explorer','Display','Theme')){throw 'GUI worker角色尚未核准。'}
 $leaf=$Role.ToLowerInvariant()
 return @('core/gui_stage_library.ps1','core/gui_worker.ps1',('modules/'+$leaf+'/'+$leaf+'_settings_library.ps1'),('modules/'+$leaf+'/native/'+$leaf+'.cs'))
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
 [string]$Role,[string]$UserSid,[int]$CallerSession,[int]$DesktopSession,[string]$Computer,[switch]$VerifyOnly,[string]$RunId=([guid]::NewGuid().ToString('D')),[ValidateSet('Save','Load','Verify')][string]$IconMode='Load',[switch]$ApplyPolicy,[switch]$NonInteractive)
 $ErrorActionPreference='Stop'
 $manifest=@(Get-SetupGuiStageFiles $Role)
 Assert-SetupGuiCaller -UserSid $UserSid -CallerSession $CallerSession -DesktopSession $DesktopSession -Computer $Computer
 Assert-SetupGuiAncestors $CommonDataRoot
 $paths=Get-SetupGuiRunPaths -CommonDataRoot $CommonDataRoot -Role $Role -RunId $RunId
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
  if($Role -ceq 'Start'){$context|Add-Member ApplyPolicy ([bool]$ApplyPolicy);$context|Add-Member NonInteractive ([bool]($NonInteractive -or ($ApplyPolicy -and $CallerSession -eq 0)))}
  if($Role -cin @('Desktop','Icons')){$context|Add-Member SourcePackageRoot ([IO.Path]::GetFullPath($SourceRoot))}
  if($Role -ceq 'Icons'){
   if($VerifyOnly){$IconMode='Verify'}elseif($IconMode -ceq 'Verify'){throw '圖示 Verify 必須使用唯讀驗收模式。'}
   $context|Add-Member IconMode $IconMode
   if($IconMode -cne 'Save'){
    $referencePath=Join-Path $SourceRoot 'modules/desktop/desktop_layout.json';Assert-SetupGuiPlainPath $referencePath
    $digest=(Get-FileHash -LiteralPath $referencePath -Algorithm SHA256).Hash
    $reference=Get-Content -LiteralPath $referencePath -Raw -Encoding UTF8|ConvertFrom-Json
    if((Get-FileHash -LiteralPath $referencePath -Algorithm SHA256).Hash -cne $digest){throw '圖示來源範本讀取期間改變。'}
    Assert-SetupIconReference $reference
    $context|Add-Member IconReference $reference
   }
  }
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
 if($Role -ceq 'Start' -and ($context.ApplyPolicy -isnot [bool] -or $context.NonInteractive -isnot [bool])){throw 'GUI worker開始選單模式格式不符。'}
 if($Role -cin @('Desktop','Icons')){if([string]::IsNullOrWhiteSpace($context.SourcePackageRoot) -or [IO.Path]::GetFullPath($context.SourcePackageRoot) -cne $context.SourcePackageRoot){throw 'GUI worker原始套件來源格式不符。'};Assert-SetupGuiPlainPath $context.SourcePackageRoot}
 if($Role -ceq 'Icons'){
  if($context.IconMode -cnotin @('Save','Load','Verify') -or ($context.VerifyOnly -ne ($context.IconMode -ceq 'Verify'))){throw 'GUI worker圖示模式不符。'}
  if($context.IconMode -cne 'Save'){Assert-SetupIconReference $context.IconReference}elseif($context.PSObject.Properties['IconReference']){throw '圖示 Save 不可載入 staged 範本。'}
 }
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
 if($Context.VerifyOnly){return ($Context.Role+'-Verification.json')}
 return ($Context.Role+'-Result.json')
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
 if($context.Role -ceq 'Icons' -and $result.Mode -cne $context.IconMode){throw 'GUI worker結果圖示模式不符。'}
 if($context.Role -ceq 'Start'){Assert-SetupGuiStartResult $result}
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
function Assert-SetupGuiStartResult {
 param($Result)
 if($Result.Success -isnot [bool] -or $Result.Status -cnotin @('Confirmed','LegacyPendingApply','PendingSignIn','Failed') -or $Result.Success -ne ($Result.Status -ceq 'Confirmed')){throw 'GUI worker開始選單結果狀態與成功值不符。'}
}
function Test-SetupGuiPendingResult {
 param([string]$Role,$Result)
 return ($Role -ceq 'Start' -and $Result.Success -is [bool] -and -not $Result.Success -and $Result.Status -cin @('LegacyPendingApply','PendingSignIn'))
}
function Invoke-SetupGuiRole {
 param([Parameter(Mandatory=$true)][string]$PackageRoot,[string]$Role,[switch]$Worker,[switch]$VerifyOnly,[string]$VerificationRunId,[ValidateSet('Save','Load','Verify')][string]$IconMode='Load',[switch]$ApplyPolicy,[switch]$NonInteractive)
 $ErrorActionPreference='Stop'
 $null=Get-SetupGuiStageFiles $Role
 $scope=Get-SetupGuiIdentity
 if($Worker -and $scope.SessionId -eq 0){throw 'GUI -Worker不能在session 0繞過原使用者桌面身分。'}
 $desktop=Get-SetupGuiDesktopSession $scope
 $creation=@{SourceRoot=$PackageRoot;CommonDataRoot=$scope.CommonDataRoot;Role=$Role;UserSid=$scope.UserSID;CallerSession=$scope.SessionId;DesktopSession=$desktop;Computer=$scope.Computer;VerifyOnly=[bool]$VerifyOnly}
 if($Role -ceq 'Icons'){$creation.IconMode=$IconMode}
 if($Role -ceq 'Start'){$creation.ApplyPolicy=[bool]$ApplyPolicy;$creation.NonInteractive=[bool]$NonInteractive}
 if($VerificationRunId){$requested=[guid]::Empty;if(-not [guid]::TryParse($VerificationRunId,[ref]$requested)){throw 'GUI 驗證本輪ID格式不符。'};$creation.RunId=$requested.ToString('D')}
 $stage=New-SetupGuiStage @creation
 try{
  $context=Read-SetupGuiContext -CodeRoot $stage.CodeRoot -CommonDataRoot $stage.CommonDataRoot -Role $Role -RunId $stage.Context.RunId
  if(($context|ConvertTo-Json -Depth 8 -Compress) -cne ($stage.Context|ConvertTo-Json -Depth 8 -Compress)){throw 'GUI worker啟動前context已改變。'}
  if($scope.SessionId -eq 0){Invoke-SetupGuiScheduledWorker -Stage $stage -Scope $scope}else{Invoke-SetupGuiLocalWorker -Stage $stage -Scope $scope}
  $result=Read-SetupGuiResult -Stage $stage
  if(-not $result.Success -and -not(Test-SetupGuiPendingResult -Role $Role -Result $result)){throw $result.Error}
  if($Role -ceq 'Icons' -and $stage.Context.IconMode -ceq 'Save'){Write-SetupIconReference -PackageRoot $stage.Context.SourcePackageRoot -Reference $result.Reference}
  return $result
 }finally{$stage.Lock.Dispose()}
}
function Invoke-SetupGuiFreshVerification {
 param([Parameter(Mandatory=$true)][string]$PackageRoot,[Parameter(Mandatory=$true)][ValidateSet('Display','Theme','Desktop','Icons','Start')][string]$Role)
 $scope=Get-SetupGuiIdentity
 $run=[guid]::NewGuid().ToString('D')
 $result=Invoke-SetupGuiRole -PackageRoot $PackageRoot -Role $Role -VerifyOnly -VerificationRunId $run
 if($null -eq $result -or $result -is [array] -or $result.Schema -ne 1 -or $result.RunId -cne $run -or $result.Role -cne $Role -or $result.UserSID -cne $scope.UserSID -or $result.Computer -cne $scope.Computer -or $result.SessionId -le 0 -or ($scope.SessionId -gt 0 -and $result.SessionId -ne $scope.SessionId) -or $result.VerifyOnly -isnot [bool] -or -not $result.VerifyOnly -or $result.Success -isnot [bool]){throw 'GUI 即時驗證不是本輪、原使用者、原電腦或原桌面的受保護結果。'}
 return $result
}
function Open-SetupGuiExecutionLock {
 param($Paths)
 Assert-SetupGuiProtectedPath $Paths.RoleRoot -Directory
 $path=Join-Path $Paths.RoleRoot 'execution.lock'
 if(Test-Path -LiteralPath $path){Assert-SetupGuiProtectedPath $path}
 try{$lease=[IO.File]::Open($path,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{throw 'GUI worker角色已有執行程序，未執行任何UI設定。'}
 try{Assert-SetupGuiProtectedPath $path;return $lease}catch{$lease.Dispose();throw}
}
function Get-SetupDesktopRoots {
 @([Environment]::GetFolderPath('DesktopDirectory'),[Environment]::GetFolderPath('CommonDesktopDirectory'))|Select-Object -Unique
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
  $module=Join-Path $CodeRoot ('modules/'+$(switch -CaseSensitive ($Role){Icons{'desktop'} Start{'start_menu'} default{$Role.ToLowerInvariant()}}))
  $library=switch -CaseSensitive ($Role){Explorer{'explorer_settings_library.ps1'} Display{'display_settings_library.ps1'} Theme{'theme_settings_library.ps1'} Desktop{'desktop_settings_library.ps1'} Icons{'icons_settings_library.ps1'} Start{'start_menu_settings_library.ps1'} default{throw 'GUI worker角色尚未核准。'}}
  . (Join-Path $module $library)
  $result=switch -CaseSensitive ($Role){Explorer{Invoke-SetupExplorerSettings -ModuleRoot $module -VerifyOnly:$context.VerifyOnly} Display{Invoke-SetupDisplaySettings -ModuleRoot $module -VerifyOnly:$context.VerifyOnly} Theme{Invoke-SetupThemeSettings -ModuleRoot $module -VerifyOnly:$context.VerifyOnly} Desktop{Invoke-SetupDesktopSettings -ModuleRoot $module -SourcePackageRoot $context.SourcePackageRoot -DesktopRoots @(Get-SetupDesktopRoots) -VerifyOnly:$context.VerifyOnly} Icons{Invoke-SetupIconsSettings -ModuleRoot $module -Mode $context.IconMode -Reference $context.IconReference} Start{Invoke-SetupStartMenuSettings -ModuleRoot $module -OutputRoot $paths.DataRoot -VerifyOnly:$context.VerifyOnly -ApplyPolicy:$context.ApplyPolicy -NonInteractive:$context.NonInteractive}}
  if($result.Success -isnot [bool]){throw 'GUI worker葉節點未提供有效成功狀態。'}
  if($Role -ceq 'Start'){Assert-SetupGuiStartResult $result}
  $details=[ordered]@{};foreach($property in $result.PSObject.Properties){$details[$property.Name]=$property.Value}
  Write-SetupGuiResult -DataRoot $paths.DataRoot -Context $context -Result $details
  $published=$true
  if(-not $result.Success -and -not(Test-SetupGuiPendingResult -Role $Role -Result $result)){throw $result.Error}
  return $result
 }catch{
  if(-not $published){$failure=@{Success=$false;Error=$_.Exception.Message;FailedAt=(Get-Date).ToString('o')};if($Role -ceq 'Start'){$failure.Status='Failed'};Write-SetupGuiResult -DataRoot $paths.DataRoot -Context $context -Result $failure}
  throw
 }finally{if($lease){$lease.Dispose()}}
}
