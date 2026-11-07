#Requires -Version 5.1
#Requires -RunAsAdministrator
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'sync_custom_hosts.ps1')
$mutex=New-Object Threading.Mutex($false,'Global\CustomHostsSync-NUC')
$owned=$false
try{
 try{$owned=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
 if(-not $owned){exit 0}
 $runtime=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'runtime.json'))|ConvertFrom-Json
 $profileRegistry=Get-ItemProperty ('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\'+$runtime.OwnerSID)
 $actualProfile=[Environment]::ExpandEnvironmentVariables($profileRegistry.ProfileImagePath)
 if([IO.Path]::GetFullPath($actualProfile).TrimEnd('\') -ine [IO.Path]::GetFullPath($runtime.ProfilePath).TrimEnd('\')){throw 'Owner SID 與使用者家目錄不一致。'}
 $expectedHosts=Join-Path $env:WINDIR 'System32\drivers\etc\hosts'
 if([IO.Path]::GetFullPath($runtime.HostsPath) -ine [IO.Path]::GetFullPath($expectedHosts)){throw '系統 hosts 路徑不符。'}
 while($true){
  $seconds=10
  try{
   $status=Invoke-CustomHostsSync -ProfilePath $runtime.ProfilePath -StatePath $PSScriptRoot -TargetHostsPath $runtime.HostsPath
   $seconds=[int]$status.PollSeconds
  }catch{
   @{Success=$false;FailedAt=(Get-Date).ToString('o');Error=$_.Exception.Message}|ConvertTo-Json|Set-Content (Join-Path $PSScriptRoot 'last-error.json') -Encoding UTF8
  }
  Start-Sleep -Seconds $seconds
 }
}catch{
 @{Success=$false;FailedAt=(Get-Date).ToString('o');Error=$_.Exception.Message}|ConvertTo-Json|Set-Content (Join-Path $PSScriptRoot 'watcher-fatal-error.json') -Encoding UTF8
 throw
}finally{if($owned){$mutex.ReleaseMutex()};$mutex.Dispose()}



