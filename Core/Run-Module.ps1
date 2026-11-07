param([Parameter(Mandatory=$true)][string]$Module,[switch]$VerifyOnly,[switch]$SyncOnly,[ValidateSet('All','Hosts','SSH')][string]$Mode='All')
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')
$allowed=@('Apply-HostsSync','Remove-OneDrive','Remove-SetupResidue','Apply-ExplorerSettings','Apply-TerminalHotkey','Apply-InputMethodSettings','Apply-StartMenuSettings','Apply-AMDPrivacySettings','Apply-CopilotSettings','Apply-AutologonSettings','Apply-PowerSettings','Apply-SSHSettings','Install-Drivers','Install-WindowsUpdates','Apply-Debloat','Apply-TaskbarSettings','Apply-DisplaySettings','Apply-DesktopSettings','Apply-ThemeSettings','Desktop-IconLayout','Apply-PagefileSettings')
if($Module -notin $allowed){throw 'Unknown module'}
if($Module -ne 'Apply-HostsSync' -and ($SyncOnly -or $Mode -ne 'All')){throw 'SyncOnly/Mode only apply to Apply-HostsSync.'}
$isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $isAdmin){
 $arguments='-NoProfile -NoExit -ExecutionPolicy Bypass -File "'+$PSCommandPath+'" -Module "'+$Module+'"'
 if($VerifyOnly){$arguments+=' -VerifyOnly'}
 if($Module -eq 'Apply-HostsSync'){$arguments+=' -Mode '+$Mode;if($SyncOnly){$arguments+=' -SyncOnly'}}
 Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments;return
}
$path=Resolve-NucPath ($Module+'.ps1')
if($Module -eq 'Apply-HostsSync'){
 $options=@{Mode=$Mode}
 if($VerifyOnly){$options.VerifyOnly=$true}elseif($SyncOnly){$options.SyncOnly=$true}
 & $path @options
}elseif($VerifyOnly){
 if($Module -eq 'Desktop-IconLayout'){& $path -Mode Verify}
 else{if(-not (Get-Command $path).Parameters.ContainsKey('VerifyOnly')){throw 'This module does not support VerifyOnly. Use Windows.cmd -VerifyOnly.'};& $path -VerifyOnly}
}else{& $path}
