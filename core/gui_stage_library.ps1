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
