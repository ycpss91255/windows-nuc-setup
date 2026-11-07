param([Parameter(Mandatory=$true)][string]$Module,[switch]$VerifyOnly,[switch]$SyncOnly,[ValidateSet('All','Hosts','SSH')][string]$Mode='All',[string]$DriverPackagePath)
$ErrorActionPreference='Stop'
if($DriverPackagePath){$DriverPackagePath=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DriverPackagePath)}
. (Join-Path $PSScriptRoot 'Paths.ps1')
$allowed=@('Apply-HostsSync','Remove-OneDrive','Remove-SetupResidue','Apply-ExplorerSettings','Apply-TerminalHotkey','Apply-InputMethodSettings','Apply-StartMenuSettings','Apply-AMDPrivacySettings','Apply-CopilotSettings','Apply-AutologonSettings','Apply-PowerSettings','Apply-SSHSettings','Install-Drivers','Install-WindowsUpdates','Apply-Debloat','Apply-TaskbarSettings','Apply-DisplaySettings','Apply-DesktopSettings','Apply-ThemeSettings','Desktop-IconLayout','Apply-PagefileSettings')
if($Module -notin $allowed){throw 'Unknown module'}
if($Module -ne 'Apply-HostsSync' -and ($SyncOnly -or $Mode -ne 'All')){throw 'SyncOnly/Mode only apply to Apply-HostsSync.'}
$isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $isAdmin){
 $command="& '"+$PSCommandPath.Replace("'","''")+"' -Module '"+$Module.Replace("'","''")+"'"
 if($VerifyOnly){$command+=' -VerifyOnly'}
 if($Module -eq 'Apply-HostsSync'){$command+=' -Mode '+$Mode;if($SyncOnly){$command+=' -SyncOnly'}}
 if($DriverPackagePath){$command+=" -DriverPackagePath '"+$DriverPackagePath.Replace("'","''")+"'"}
 Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -NoExit -ExecutionPolicy Bypass -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)));return
}
$path=Resolve-NucPath ($Module+'.ps1')
if($Module -eq 'Apply-HostsSync'){
 $options=@{Mode=$Mode}
 if($VerifyOnly){$options.VerifyOnly=$true}elseif($SyncOnly){$options.SyncOnly=$true}
 & $path @options
}elseif($VerifyOnly){
 if($Module -eq 'Desktop-IconLayout'){& $path -Mode Verify}
 else{if(-not (Get-Command $path).Parameters.ContainsKey('VerifyOnly')){throw 'This module does not support VerifyOnly. Use Windows.cmd -VerifyOnly.'};& $path -VerifyOnly}
}else{if($Module -eq 'Install-Drivers'){& $path -DriverPackagePath $DriverPackagePath}else{& $path}}
