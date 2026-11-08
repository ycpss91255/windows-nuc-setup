param([Parameter(Mandatory=$true)][string]$Module,[switch]$VerifyOnly,[switch]$SyncOnly,[ValidateSet('All','Hosts','SSH')][string]$Mode='All',[string]$DriverPackagePath,[string]$ExpectedUserSID,[string]$ConfirmedBoard,[string]$ConfirmationComputer)
$ErrorActionPreference='Stop'
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($ExpectedUserSID -and $ExpectedUserSID -ne $sid){throw '請用原本登入帳號提權，不可改用另一個管理員帳號執行獨立模組。'}
if($DriverPackagePath){$DriverPackagePath=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DriverPackagePath)}
. (Join-Path $PSScriptRoot 'paths.ps1')
$allowed=@('Apply-HostsSync','Remove-OneDrive','Remove-SetupResidue','Apply-ExplorerSettings','Apply-TerminalHotkey','Apply-InputMethodSettings','Apply-StartMenuSettings','Apply-AMDPrivacySettings','Apply-CopilotSettings','Apply-AutologonSettings','Apply-PowerSettings','Apply-SSHSettings','Install-Drivers','Install-WindowsUpdates','Apply-Debloat','Apply-TaskbarSettings','Apply-DisplaySettings','Apply-DesktopSettings','Apply-ThemeSettings','Desktop-IconLayout','Apply-PagefileSettings')
if($Module -notin $allowed){throw 'Unknown module'}
if($Module -ne 'Apply-HostsSync' -and ($SyncOnly -or $Mode -ne 'All')){throw 'SyncOnly/Mode only apply to Apply-HostsSync.'}
$isAdmin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if(-not $isAdmin){
 $command="& '"+$PSCommandPath.Replace("'","''")+"' -Module '"+$Module.Replace("'","''")+"'"
 $command+=" -ExpectedUserSID '"+$sid.Replace("'","''")+"'"
 if($VerifyOnly){$command+=' -VerifyOnly'}
 if($Module -eq 'Apply-HostsSync'){$command+=' -Mode '+$Mode;if($SyncOnly){$command+=' -SyncOnly'}}
 if($DriverPackagePath){$command+=" -DriverPackagePath '"+$DriverPackagePath.Replace("'","''")+"'"}
 if($ConfirmedBoard){$command+=" -ConfirmedBoard '"+$ConfirmedBoard.Replace("'","''")+"' -ConfirmationComputer '"+$ConfirmationComputer.Replace("'","''")+"'"}
 Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -NoExit -ExecutionPolicy Bypass -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)));return
}
$path=Resolve-NucPath ($Module+'.ps1')
if($Module -eq 'Apply-HostsSync'){
 $options=@{Mode=$Mode}
 if($VerifyOnly){$options.VerifyOnly=$true}elseif($SyncOnly){$options.SyncOnly=$true}
 & $path @options
}elseif($VerifyOnly){
 if($Module -eq 'Desktop-IconLayout'){& $path -Mode Verify}
 else{if(-not (Get-Command $path).Parameters.ContainsKey('VerifyOnly')){throw 'This module does not support VerifyOnly. Use windows.cmd -VerifyOnly.'};& $path -VerifyOnly}
}else{if($Module -eq 'Install-Drivers'){& $path -DriverPackagePath $DriverPackagePath -ConfirmedBoard $ConfirmedBoard -ConfirmationComputer $ConfirmationComputer}else{& $path}}
