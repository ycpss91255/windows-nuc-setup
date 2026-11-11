#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
function Reject([scriptblock]$Action,[string]$Name,[string]$Expected){$errorRecord=$null;try{& $Action|Out-Null}catch{$errorRecord=$_};Assert ($null -ne $errorRecord -and -not($errorRecord.Exception -is [Management.Automation.ParameterBindingException]) -and $errorRecord.Exception.Message.Contains($Expected)) $Name}
$lib=Join-Path $root 'modules/updates/update_stage_library.ps1'
Assert (Test-Path $lib) 'SYSTEM staging有獨立安全具名來源'
. $lib
$acl=New-SetupUpdateDirectorySecurity
Assert-SetupUpdateAcl -Acl $acl -Directory
Assert ($acl.AreAccessRulesProtected -and $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -eq 'S-1-5-32-544') '新目錄ACL在建立前就保護繼承與admin擁有者'
foreach($sid in @('S-1-1-0','S-1-5-11','S-1-5-32-545','S-1-5-21-1-2-3-1001')){
 $bad=New-SetupUpdateDirectorySecurity;$bad.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)),'Modify','ContainerInherit,ObjectInherit','None','Allow')))
 Reject {Assert-SetupUpdateAcl -Acl $bad -Directory} ('拒絕非trusted SID可修改SYSTEM來源 '+$sid) 'ACL'
}
$bad=New-SetupUpdateDirectorySecurity;$bad.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-21-1-2-3-1001')))
Reject {Assert-SetupUpdateAcl -Acl $bad -Directory} '拒絕一般使用者擁有stage' '擁有者'
$parent=New-SetupUpdateDirectorySecurity;$users=New-Object Security.Principal.SecurityIdentifier('S-1-5-32-545')
$parent.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($users,'CreateDirectories','None','None','Allow')))
Assert-SetupUpdateAcl -Acl $parent -Ancestor
Assert $true '合法父目錄一般使用者只能建立子目錄不誤拒'
$parent.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($users,'DeleteSubdirectoriesAndFiles','None','None','Allow')))
Reject {Assert-SetupUpdateAcl -Acl $parent -Ancestor} '父目錄DeleteChild可替換stage必拒絕' '父目錄'
$parent=New-SetupUpdateDirectorySecurity;$parent.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($users,'FullControl','ContainerInherit,ObjectInherit','InheritOnly','Allow')))
Assert-SetupUpdateAcl -Acl $parent -Ancestor
Assert $true '父目錄InheritOnly不是作用於父目錄本身的DeleteChild'
$d=Join-Path ([IO.Path]::GetTempPath()) ('stage_acl_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($d)
$untrusted=Join-Path $d 'existing';[void][IO.Directory]::CreateDirectory($untrusted);[IO.File]::WriteAllText((Join-Path $untrusted 'keep.txt'),'keep')
$ownedAcl=Get-Acl -LiteralPath $untrusted;$ownedAcl.SetOwner([Security.Principal.WindowsIdentity]::GetCurrent().User);Set-Acl -LiteralPath $untrusted -AclObject $ownedAcl
Reject {Assert-SetupUpdateProtectedPath -Path $untrusted -Directory} '真正一般user擁有TEMP目錄拒絕SYSTEM來源' '擁有者'
Assert ([IO.File]::ReadAllText((Join-Path $untrusted 'keep.txt')) -eq 'keep') '拒絕時保留原檔不接管ACL'
$link=Join-Path $d 'linked';$null=New-Item -ItemType Junction -Path $link -Target $untrusted
Reject {Assert-SetupUpdatePlainPath $link} '實體junction拒絕' '重新解析'
Reject {Assert-SetupUpdatePlainPath (Join-Path $link 'child.ps1')} '不存在子檔仍檢查祖先junction' '重新解析'
# Native positive creation is only meaningful in an elevated token; this host may be standard user.
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if($admin){$native=Join-Path $d 'native_protected';New-SetupUpdateProtectedDirectory $native;Assert-SetupUpdateProtectedPath $native -Directory;Assert $true '提升權限CI以真DirectorySecurity原子建立及讀回'}else{Write-Host 'NATIVE_ADMIN_CREATE_NOT_RUN: standard token; no elevation attempted'}
Write-Host ('SAFE ACL FIXTURE='+$d)