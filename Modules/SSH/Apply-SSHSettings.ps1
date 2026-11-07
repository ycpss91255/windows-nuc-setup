#Requires -Version 5.1
#Requires -RunAsAdministrator
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'Initialize-SSHClient.ps1')
$capability=Get-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
if($capability.State -ne 'Installed'){
 Write-Host '正在安裝 OpenSSH Server；若元件尚未快取，需要連網下載。' -ForegroundColor Cyan
 $result=Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
 if($result.RestartNeeded){throw 'SSH 元件需要重新開機後才能繼續設定。'}
}
Set-Service sshd -StartupType Automatic
Start-Service sshd
$name='OpenSSH-Server-In-TCP'
if(Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue){Set-NetFirewallRule -Name $name -Enabled True -Direction Inbound -Action Allow -Profile Any -RemoteAddress LocalSubnet}
else{New-NetFirewallRule -Name $name -DisplayName 'OpenSSH Server (sshd)' -Enabled True -Direction Inbound -Protocol TCP -LocalPort 22 -Action Allow -Profile Any -RemoteAddress LocalSubnet|Out-Null}
if((Get-Service sshd).Status -ne 'Running'){throw 'SSH 服務尚未正常啟動。'}
Write-Host 'SSH 已啟動、設為自動啟動，防火牆僅允許本機子網路。' -ForegroundColor Green
Get-NetIPAddress -AddressFamily IPv4|Where-Object {$_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254.*'}|Select-Object InterfaceAlias,IPAddress|Format-Table|Out-Host

& (Join-Path $PSScriptRoot 'Apply-LANPingSettings.ps1')


& (Join-Path $PSScriptRoot 'Apply-HostsSync.ps1')

