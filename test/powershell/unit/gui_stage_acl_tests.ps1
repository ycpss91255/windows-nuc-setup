#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name};$script:count++}
function Reject([scriptblock]$Action,[string]$Expected,[string]$Name){$failure=$null;try{& $Action|Out-Null}catch{$failure=$_};Assert ($null -ne $failure -and $failure.Exception -isnot [Management.Automation.ParameterBindingException] -and $failure.Exception.Message.Contains($Expected)) ($Name+'; actual='+$failure.Exception.Message)}
. (Join-Path $root 'core/gui_stage_library.ps1')
$user='S-1-5-21-1-2-3-1001';$code=New-SetupGuiDirectorySecurity
Assert-SetupGuiAcl -Acl $code -Directory
Assert ($code.AreAccessRulesProtected -and $code.GetOwner([Security.Principal.SecurityIdentifier]).Value -eq 'S-1-5-32-544') 'GUI code directory starts with protected BA-owned security descriptor'
$data=New-SetupGuiDirectorySecurity -UserSid $user
Assert-SetupGuiAcl -Acl $data -Directory -UserSid $user
$rules=@($data.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])|Where-Object {$_.IdentityReference.Value -eq $user})
Assert ($rules.Count -eq 1 -and ($rules[0].FileSystemRights -band [Security.AccessControl.FileSystemRights]::ReadAndExecute) -eq [Security.AccessControl.FileSystemRights]::ReadAndExecute -and -not($rules[0].FileSystemRights -band [Security.AccessControl.FileSystemRights]::Write)) 'GUI data grants only original user read/execute without write'
foreach($sid in @('S-1-1-0','S-1-5-11','S-1-5-32-545',$user)){
 $bad=New-SetupGuiDirectorySecurity;$bad.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)),'Modify','ContainerInherit,ObjectInherit','None','Allow')))
 Reject {Assert-SetupGuiAcl -Acl $bad -Directory} 'ACL' ('nontrusted identity cannot modify GUI code '+$sid)
}
$bad=New-SetupGuiDirectorySecurity -UserSid $user;$bad.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($user)),'WriteData','None','None','Allow')))
Reject {Assert-SetupGuiAcl -Acl $bad -Directory -UserSid $user} 'ACL' 'original user cannot write GUI policy or report data'
$bad=New-SetupGuiDirectorySecurity;$bad.SetOwner((New-Object Security.Principal.SecurityIdentifier($user)))
Reject {Assert-SetupGuiAcl -Acl $bad -Directory} '擁有者' 'GUI staging never takes over an untrusted existing directory'
$bad=New-SetupGuiDirectorySecurity;$bad.SetAccessRuleProtection($false,$true)
Reject {Assert-SetupGuiAcl -Acl $bad -Directory} '繼承' 'GUI code directory must disable inherited access'
$bad=New-SetupGuiDirectorySecurity;$bad.RemoveAccessRuleAll((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier('S-1-5-18')),'FullControl','ContainerInherit,ObjectInherit','None','Allow')))
Reject {Assert-SetupGuiAcl -Acl $bad -Directory} '完整權限' 'SYSTEM full control is mandatory'
$ancestor=New-SetupGuiDirectorySecurity;$users=New-Object Security.Principal.SecurityIdentifier('S-1-5-32-545');$ancestor.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($users,'CreateDirectories','None','None','Allow')))
Assert-SetupGuiAcl -Acl $ancestor -Ancestor
Assert $true 'ancestor create-child rights alone cannot replace protected GUI stage'
$ancestor.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($users,'DeleteSubdirectoriesAndFiles','None','None','Allow')))
Reject {Assert-SetupGuiAcl -Acl $ancestor -Ancestor} '父目錄' 'ancestor delete-child rights cannot replace GUI code'
Reject {Assert-SetupGuiPlainPath '\\server\share\worker.ps1'} '本機絕對' 'GUI worker cannot run from UNC path'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('gui_acl_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
$existing=Join-Path $temp 'user-owned';[void][IO.Directory]::CreateDirectory($existing);[IO.File]::WriteAllText((Join-Path $existing 'keep.txt'),'keep')
$owner=Get-Acl -LiteralPath $existing
if($owner.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin @('S-1-5-18','S-1-5-32-544')){Reject {New-SetupGuiProtectedDirectory $existing} '擁有者' 'native untrusted TEMP directory remains untouched';Assert ([IO.File]::ReadAllText((Join-Path $existing 'keep.txt')) -eq 'keep') 'rejection preserves existing contents'}
$link=Join-Path $temp 'junction';$null=New-Item -ItemType Junction -Path $link -Target $existing
Reject {Assert-SetupGuiPlainPath (Join-Path $link 'missing.ps1')} '重新解析' 'GUI source rejects junction ancestors even for nonexistent child'
$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if($admin){$native=Join-Path $temp 'native_code';New-SetupGuiProtectedDirectory $native;Assert-SetupGuiProtectedPath $native -Directory;$nativeData=Join-Path $temp 'native_data';New-SetupGuiProtectedDirectory $nativeData -UserSid $user;Assert-SetupGuiProtectedPath $nativeData -Directory -UserSid $user;Assert $true 'elevated Windows creates code/data with native descriptor and validates actual ACL'}else{Write-Host 'NATIVE_ADMIN_CREATE_NOT_RUN: standard token; no elevation attempted'}
Write-Host ('ALL PASS: '+$script:count+' GUI ACL assertions; only isolated TEMP objects and in-memory security descriptors')