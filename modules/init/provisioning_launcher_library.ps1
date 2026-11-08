#Requires -Version 5.1
# Definitions only. The public file contains a fixed bootstrap, never credentials.
function Get-InitPublicLauncherText {
 param([string]$StageRoot)
 $stage=[IO.Path]::GetFullPath($StageRoot).TrimEnd('\')
 $entry=(Join-Path $stage 'runtime\modules\init\initialize_nuc.ps1').Replace("'","''")
 $state=(Join-Path $stage 'state.json').Replace("'","''")
 $shell=Join-Path ([Environment]::GetFolderPath('System')) 'WindowsPowerShell\v1.0\powershell.exe'
 $bootstrap=@'
$ErrorActionPreference='Stop'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$entry='__ENTRY__'
$state='__STATE__'
$command="& '"+$entry.Replace("'","''")+"' -ResumeStatePath '"+$state.Replace("'","''")+"' -ExpectedUserSID '"+$sid+"'"
$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
Start-Process -FilePath '__SHELL__' -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -EncodedCommand '+$encoded) -Wait
'@
 $bootstrap=$bootstrap.Replace('__ENTRY__',$entry).Replace('__STATE__',$state).Replace('__SHELL__',$shell.Replace("'","''"))
 $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($bootstrap))
 return '@echo off'+"`r`n"+'"'+$shell+'" -NoProfile -ExecutionPolicy Bypass -EncodedCommand '+$encoded+"`r`n"
}
function Protect-InitPublicLauncher {
 param([string]$Path)
 $acl=New-Object Security.AccessControl.FileSecurity
 $acl.SetAccessRuleProtection($true,$false)
 $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
 foreach($sid in @('S-1-5-18','S-1-5-32-544')){
  $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)),'FullControl','Allow')))
 }
 $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-545')),'ReadAndExecute','Allow')))
 Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
}
function Assert-InitPublicLauncherAcl {
 param([string]$Path)
 $acl=Get-Acl -LiteralPath $Path -ErrorAction Stop
 if(-not $acl.AreAccessRulesProtected -or $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin @('S-1-5-18','S-1-5-32-544')){throw '公開 Init 啟動器的擁有者或繼承權限不可信。'}
 $rules=@($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))
 if($rules.Count -ne 3){throw '公開 Init 啟動器 ACL 數量不符。'}
 foreach($sid in @('S-1-5-18','S-1-5-32-544','S-1-5-32-545')){
  $expected=if($sid -eq 'S-1-5-32-545'){[Security.AccessControl.FileSystemRights]::ReadAndExecute -bor [Security.AccessControl.FileSystemRights]::Synchronize}else{[Security.AccessControl.FileSystemRights]::FullControl}
  $matching=@($rules|Where-Object {$_.IdentityReference.Value -eq $sid -and $_.AccessControlType -eq 'Allow' -and $_.FileSystemRights -eq $expected -and $_.PropagationFlags -eq 'None' -and $_.InheritanceFlags -eq 'None'})
  if($matching.Count -ne 1){throw '公開 Init 啟動器必須只有 SYSTEM／管理員可寫，Users 唯讀執行。'}
 }
}
function Assert-InitPublicLauncher {
 param([string]$StageRoot,[string]$Path)
 $expectedPath=[IO.Path]::GetFullPath($StageRoot).TrimEnd('\')+'.cmd'
 if([IO.Path]::GetFullPath($Path) -ine $expectedPath){throw '公開啟動器位置不符。'}
 Assert-InitPlainPath $Path
 Assert-InitPublicLauncherAcl $Path
 $expected=[Text.Encoding]::ASCII.GetBytes((Get-InitPublicLauncherText $StageRoot))
 $actual=[IO.File]::ReadAllBytes($Path)
 $sha=[Security.Cryptography.SHA256]::Create()
 try{if([Convert]::ToBase64String($sha.ComputeHash($actual)) -cne [Convert]::ToBase64String($sha.ComputeHash($expected))){throw '公開 Init 啟動器內容已改變，拒絕覆寫或執行。'}}finally{$sha.Dispose()}
}
function New-InitPublicLauncher {
 param([string]$StageRoot)
 $stage=[IO.Path]::GetFullPath($StageRoot).TrimEnd('\')
 Assert-InitPlainPath $stage
 Assert-InitProtectedDirectory $stage
 $path=$stage+'.cmd';Assert-InitPlainPath $path
 if(Test-Path -LiteralPath $path){Assert-InitPublicLauncher $stage $path;return $path}
 # Create privately, set the final restrictive ACL, then publish without overwrite.
 $temporary=Join-Path $stage ('public_launcher.'+[guid]::NewGuid().ToString('N')+'.tmp')
 try{
  [IO.File]::WriteAllText($temporary,(Get-InitPublicLauncherText $stage),[Text.Encoding]::ASCII)
  Protect-InitPublicLauncher $temporary
  Assert-InitPublicLauncherAcl $temporary
  [IO.File]::Move($temporary,$path)
  Assert-InitPublicLauncher $stage $path
  return $path
 }finally{if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary -Force}}
}
