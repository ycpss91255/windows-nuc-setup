#Requires -Version 5.1
param([string]$UserName=$env:USERNAME,[string]$AutoLogonPassword,[string]$DriverPackagePath,[string]$ExpectedUserSID,[string]$ConfirmedBoard,[string]$ConfirmationComputer,[switch]$NonInteractive)
$ErrorActionPreference='Stop'
$currentSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
if($ExpectedUserSID -and $ExpectedUserSID -ne $currentSID){throw '提權後帳號已改變，請使用原帳號的管理員權限。'}
if($DriverPackagePath){$DriverPackagePath=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DriverPackagePath)}
. (Join-Path $PSScriptRoot 'paths.ps1')
Initialize-NucReports
$hardware=Get-SetupHardwareProfile -DriverPackagePath $DriverPackagePath -ConfirmedBoard $ConfirmedBoard -ConfirmationComputer $ConfirmationComputer
$skippedModules=@()
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $command="& '"+$PSCommandPath.Replace("'","''")+"' -ExpectedUserSID '"+$currentSID+"' -DriverPackagePath '"+$DriverPackagePath.Replace("'","''")+"'"
 if($ConfirmedBoard){$command+=" -ConfirmedBoard '"+$ConfirmedBoard.Replace("'","''")+"' -ConfirmationComputer '"+$ConfirmationComputer.Replace("'","''")+"'"}
 if($NonInteractive){$command+=' -NonInteractive'}
    Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)))
    exit
}
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'modules\init\provisioning_library.ps1')
$null=Invoke-InitWindowsCheckpoint -StageRoot (Join-Path $env:ProgramData 'windows_setup_init')
& (Resolve-NucPath 'test_setup_prerequisites.ps1') -DriverPackagePath $DriverPackagePath -ConfirmedBoard $ConfirmedBoard -ConfirmationComputer $ConfirmationComputer
if($hardware.IsNuc8 -and $DriverPackagePath){$hardware|Add-Member -NotePropertyName DriverSelection -NotePropertyValue (New-SetupDriverSelection -PackageRoot $script:NucPackageRoot -DriverPackagePath $DriverPackagePath) -Force}
if($UserName -ine $env:USERNAME){throw '自動登入帳號必須與目前執行帳號相同。'}
. (Resolve-NucPath 'configuration_library.ps1')
try { Invoke-SetupConfiguration -Hardware $hardware -UserName $UserName -AutoLogonPassword $AutoLogonPassword -DriverPackagePath $DriverPackagePath -ConfirmedBoard $ConfirmedBoard -ConfirmationComputer $ConfirmationComputer -NonInteractive:$NonInteractive } finally { $AutoLogonPassword=$null }
