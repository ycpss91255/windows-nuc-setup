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