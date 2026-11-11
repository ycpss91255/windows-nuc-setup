#Requires -Version 5.1
# Definitions only. No directories, ACLs or tasks are changed when this file is loaded.
function Assert-SetupUpdatePlainPath {
 param([Parameter(Mandatory=$true)][string]$Path)
 $cursor=[IO.Path]::GetFullPath($Path)
 if($cursor -notmatch '^[a-zA-Z]:\\'){throw 'SYSTEM更新stage必須使用本機絕對磁碟路徑。'}
 while($cursor){
  if(Test-Path -LiteralPath $cursor){$item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop;if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw ('SYSTEM更新來源不接受重新解析點：'+$cursor)}}
  $parent=[IO.Path]::GetDirectoryName($cursor);if($parent -eq $cursor){break};$cursor=$parent
 }
}
function New-SetupUpdateDirectorySecurity {
 $acl=New-Object Security.AccessControl.DirectorySecurity
 $acl.SetAccessRuleProtection($true,$false)
 $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
 foreach($id in @('S-1-5-18','S-1-5-32-544')){$sid=New-Object Security.Principal.SecurityIdentifier($id);$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')))}
 return $acl
}
function Assert-SetupUpdateAcl {
 param([Parameter(Mandatory=$true)]$Acl,[switch]$Directory,[switch]$Ancestor)
 $trusted=@('S-1-5-18','S-1-5-32-544')
 $owners=@($trusted)
 if($Ancestor){try{$owners+=@((New-Object Security.Principal.NTAccount('NT SERVICE','TrustedInstaller')).Translate([Security.Principal.SecurityIdentifier]).Value)}catch{}}
 $owner=$Acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
 if($owner -notin $owners){throw 'SYSTEM更新路徑擁有者不可信，保留原資料並拒絕接管。'}
 $rules=@($Acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
 if($Ancestor){
  $danger=[Security.AccessControl.FileSystemRights]::Delete -bor [Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor [Security.AccessControl.FileSystemRights]::ChangePermissions -bor [Security.AccessControl.FileSystemRights]::TakeOwnership
  foreach($rule in $rules){
   if($rule.AccessControlType -eq 'Allow' -and $rule.IdentityReference.Value -notin $owners -and -not($rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) -and ($rule.FileSystemRights -band $danger)){throw 'SYSTEM更新父目錄允許非可信身分刪除或替換子目錄，拒絕使用。'}
  }
  return
 }
 if($Directory -and -not $Acl.AreAccessRulesProtected){throw 'SYSTEM更新目錄ACL未停用繼承。'}
 foreach($rule in $rules){if($rule.AccessControlType -ne 'Allow' -or $rule.IdentityReference.Value -notin $trusted){throw 'SYSTEM更新來源ACL含非預期存取規則。'}}
 foreach($sid in $trusted){
  $matches=@($rules|Where-Object {$_.IdentityReference.Value -eq $sid -and ($_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -eq [Security.AccessControl.FileSystemRights]::FullControl -and -not($_.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly)})
  if(-not $matches.Count){throw 'SYSTEM更新來源ACL缺少SYSTEM或管理員完整權限。'}
  if($Directory -and -not @($matches|Where-Object {$_.InheritanceFlags -eq ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit) -and $_.PropagationFlags -eq [Security.AccessControl.PropagationFlags]::None}).Count){throw 'SYSTEM更新目錄ACL缺少子檔繼承保護。'}
 }
}
function Assert-SetupUpdateProtectedPath {
 param([Parameter(Mandatory=$true)][string]$Path,[switch]$Directory)
 Assert-SetupUpdatePlainPath $Path
 $item=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
 if([bool]$item.PSIsContainer -ne [bool]$Directory){throw 'SYSTEM更新stage檔案或目錄類型不符。'}
 Assert-SetupUpdateAcl -Acl (Get-Acl -LiteralPath $Path -ErrorAction Stop) -Directory:$Directory
}
function Assert-SetupUpdateAncestors {
 param([Parameter(Mandatory=$true)][string]$CommonDataRoot)
 Assert-SetupUpdatePlainPath $CommonDataRoot
 $cursor=[IO.Path]::GetFullPath($CommonDataRoot)
 while($cursor){
  $item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
  if(-not $item.PSIsContainer){throw 'SYSTEM更新父路徑不是目錄。'}
  Assert-SetupUpdateAcl -Acl (Get-Acl -LiteralPath $cursor -ErrorAction Stop) -Ancestor
  $parent=[IO.Path]::GetDirectoryName($cursor);if($parent -eq $cursor){break};$cursor=$parent
 }
}
function New-SetupUpdateProtectedDirectory {
 param([Parameter(Mandatory=$true)][string]$Path)
 Assert-SetupUpdatePlainPath $Path
 if(-not(Test-Path -LiteralPath $Path)){
  $acl=New-SetupUpdateDirectorySecurity
  # The security descriptor is supplied at creation; there is no create-then-protect interval.
  [void][IO.Directory]::CreateDirectory($Path,$acl)
 }
 Assert-SetupUpdateProtectedPath -Path $Path -Directory
}
function Get-SetupUpdateStageFiles {
 return @(
  @{Source='install_windows_updates.ps1';Name='Update-Worker.ps1'},
  @{Source='update_entry_library.ps1';Name='update_entry_library.ps1'},
  @{Source='update_progress_library.ps1';Name='update_progress_library.ps1'},
  @{Source='update_worker_library.ps1';Name='update_worker_library.ps1'},
  @{Source='update_stage_library.ps1';Name='update_stage_library.ps1'},
  @{Source='native/update_callback.cs';Name='native/update_callback.cs'}
 )
}
function New-SetupUpdateStage {
 param([Parameter(Mandatory=$true)][string]$SourceRoot,[Parameter(Mandatory=$true)][string]$CommonDataRoot,
 [Parameter(Mandatory=$true)][string]$UserSid,[Parameter(Mandatory=$true)][string]$Computer)
 $ErrorActionPreference='Stop'
 $stage=Join-Path ([IO.Path]::GetFullPath($CommonDataRoot)) 'windows_setup_update'
 Assert-SetupUpdatePlainPath $stage
 Assert-SetupUpdateAncestors $CommonDataRoot
 New-SetupUpdateProtectedDirectory $stage
 $lockPath=Join-Path $stage 'stage.lock'
 if(Test-Path -LiteralPath $lockPath){Assert-SetupUpdateProtectedPath $lockPath}
 $lock=$null
 try{$lock=[IO.File]::Open($lockPath,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch{throw '更新stage已被另一個程序使用，未複製或啟動工作。'}
 try{
  Assert-SetupUpdateProtectedPath $lockPath
  Assert-SetupUpdateAncestors $CommonDataRoot
  Assert-SetupUpdateProtectedPath $stage -Directory
  $files=@()
  foreach($file in Get-SetupUpdateStageFiles){
   $source=Join-Path $SourceRoot $file.Source;$target=Join-Path $stage $file.Name
   Assert-SetupUpdatePlainPath $source
   if(-not(Test-Path -LiteralPath $source -PathType Leaf)){throw ('更新來源缺少檔案：'+$file.Source)}
   $before=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
   $parent=Split-Path $target -Parent
   if($parent -ne $stage){New-SetupUpdateProtectedDirectory $parent}
   Assert-SetupUpdatePlainPath $target
   if(Test-Path -LiteralPath $target){Assert-SetupUpdateProtectedPath $target}
   Copy-Item -LiteralPath $source -Destination $target -Force -ErrorAction Stop
   Assert-SetupUpdateProtectedPath $target
   if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -cne $before -or (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash -cne $before){throw '更新來源複製前後雜湊不符。'}
   $files+=@([pscustomobject]@{Name=$file.Name;SHA256=$before.ToLowerInvariant()})
  }
  $context=[ordered]@{Schema=1;RunId=[guid]::NewGuid().ToString();Computer=$Computer;UserSID=$UserSid;Files=$files}
  $contextPath=Join-Path $stage 'context.json';$temporary=Join-Path $stage ([guid]::NewGuid().ToString('N')+'.tmp')
  if(Test-Path -LiteralPath $contextPath){Assert-SetupUpdateProtectedPath $contextPath}
  [IO.File]::WriteAllText($temporary,($context|ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($true)))
  Assert-SetupUpdateProtectedPath $temporary
  if(Test-Path -LiteralPath $contextPath){[IO.File]::Replace($temporary,$contextPath,[Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temporary,$contextPath)}
  $verified=Read-SetupUpdateContext -StageRoot $stage
  return [pscustomobject]@{Path=$stage;Lock=$lock;Context=$verified}
 }catch{$lock.Dispose();throw}
}
function Read-SetupUpdateContext {
 param([Parameter(Mandatory=$true)][string]$StageRoot)
 Assert-SetupUpdateProtectedPath $StageRoot -Directory
 $path=Join-Path $StageRoot 'context.json';Assert-SetupUpdateProtectedPath $path
 $context=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
 $expected=@(Get-SetupUpdateStageFiles|ForEach-Object Name|Sort-Object)
 if($context.Schema -ne 1 -or $context.RunId -notmatch '^[a-fA-F0-9]{8}(-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12}$' -or $context.UserSID -notmatch '^S-1-5-\d+(-\d+)+$' -or [string]::IsNullOrWhiteSpace($context.Computer) -or (@($context.Files|ForEach-Object Name|Sort-Object) -join ',') -cne ($expected -join ',')){throw '更新context格式或來源清單不符。'}
 foreach($file in $context.Files){
  if($file.SHA256 -notmatch '^[a-f0-9]{64}$'){throw '更新context雜湊格式不符。'}
  $target=Join-Path $StageRoot $file.Name;Assert-SetupUpdateProtectedPath $target
  if((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.SHA256){throw ('更新stage執行來源雜湊不符：'+$file.Name)}
 }
 return $context
}
function Read-SetupUpdateResult {
 param([Parameter(Mandatory=$true)][string]$CommonDataRoot,[string]$LegacyRoot,
 [Parameter(Mandatory=$true)][string]$UserSid,[string]$Computer=$env:COMPUTERNAME)
 $stage=Join-Path $CommonDataRoot 'windows_setup_update'
 Assert-SetupUpdateAncestors $CommonDataRoot
 if(-not(Test-Path -LiteralPath (Join-Path $stage 'context.json'))){throw '尚未找到可確認本機本輪身分的更新context；舊紀錄保留但不能視為本輪通過。'}
 $context=Read-SetupUpdateContext $stage
 if($context.UserSID -cne $UserSid -or $context.Computer -cne $Computer){throw '更新結果身分或本輪ID不符。'}
 $path=Join-Path $stage 'WindowsUpdate-Result.json'
 if(-not(Test-Path -LiteralPath $path) -and $LegacyRoot){$path=Join-Path $LegacyRoot 'WindowsUpdate-Result.json'}
 Assert-SetupUpdateProtectedPath $path
 $result=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
 if($result.UserSID -cne $UserSid -or $result.Computer -cne $Computer -or $result.RunId -cne $context.RunId){throw '更新結果身分或本輪ID不符。'}
 if($result.SearchResultCode -ne 2){throw '更新搜尋未完整成功，不能視為沒有更新。'}
 if($result.Selected -gt 0 -and $result.DownloadResultCode -ne 2){throw '更新下載未完整成功。'}
 return $result
}