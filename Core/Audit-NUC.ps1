#Requires -Version 5.1
#Requires -RunAsAdministrator
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')
Initialize-NucReports
$report=[ordered]@{CheckedAt=(Get-Date).ToString('o');Computer=$env:COMPUTERNAME}
$report.CPU=@(Get-CimInstance Win32_Processor|Select-Object Name)
$report.OS=Get-CimInstance Win32_OperatingSystem|Select-Object Caption,Version,BuildNumber,LastBootUpTime
$report.Board=Get-CimInstance Win32_BaseBoard|Select-Object Manufacturer,Product
$report.BIOS=Get-CimInstance Win32_BIOS|Select-Object SMBIOSBIOSVersion,ReleaseDate
$report.SSH=Get-CimInstance Win32_Service -Filter "Name='sshd'"|Select-Object State,StartMode
$report.SSHFirewall=@(Get-NetFirewallRule -Name OpenSSH-Server-In-TCP -ErrorAction SilentlyContinue|Select-Object Enabled,Direction,Action,Profile)
$report.SSHScope=@(Get-NetFirewallRule -Name OpenSSH-Server-In-TCP -ErrorAction SilentlyContinue|Get-NetFirewallAddressFilter|Select-Object RemoteAddress)
$report.FirewallProfiles=@(Get-NetFirewallProfile|Select-Object Name,Enabled)
$report.Network=@(Get-NetIPAddress -AddressFamily IPv4|Select-Object InterfaceAlias,IPAddress,PrefixLength,PrefixOrigin)
$report.DHCP=@(Get-NetIPInterface -AddressFamily IPv4|Select-Object InterfaceAlias,Dhcp,ConnectionState)
$report.AutoLogon=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'|Select-Object AutoAdminLogon,DefaultUserName,DefaultDomainName,AutoLogonCount
$report.User=Get-LocalUser -SID ([Security.Principal.WindowsIdentity]::GetCurrent().User)|Select-Object Name,Enabled,PasswordRequired,PasswordExpires,AccountExpires
$report.ProblemDevices=@(Get-PnpDevice -PresentOnly|Where-Object Status -ne OK|Select-Object Status,Class,FriendlyName,InstanceId)
$report.Displays=@(Get-CimInstance Win32_VideoController|Select-Object Name,DriverVersion,ConfigManagerErrorCode)
$report.Disks=@(Get-PhysicalDisk|Select-Object FriendlyName,HealthStatus,OperationalStatus,Size)
$report.SystemVolume=Get-Volume -DriveLetter $env:SystemDrive.TrimEnd(':')|Select-Object Size,SizeRemaining,HealthStatus
try{$report.BitLocker=Get-BitLockerVolume -MountPoint $env:SystemDrive|Select-Object MountPoint,VolumeStatus,ProtectionStatus,EncryptionPercentage}catch{$report.BitLocker=$_.Exception.Message}
try{$report.TPM=Get-Tpm|Select-Object TpmPresent,TpmReady,TpmEnabled}catch{$report.TPM=$_.Exception.Message}
try{$report.SecureBoot=Confirm-SecureBootUEFI}catch{$report.SecureBoot=$_.Exception.Message}
$report.RebootRequired=((Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'))
$report.UpdateTask=@(Get-ScheduledTask -TaskName NUC8-Setup-WindowsUpdate -ErrorAction SilentlyContinue|Select-Object State)
$report.UpdateResult=if(Test-Path (Join-Path $env:ProgramData 'NUC8-Setup\WindowsUpdate\WindowsUpdate-Result.json')){Get-Content (Join-Path $env:ProgramData 'NUC8-Setup\WindowsUpdate\WindowsUpdate-Result.json') -Raw|ConvertFrom-Json}else{$null}
$report|ConvertTo-Json -Depth 7|Set-Content (Resolve-NucPath 'Audit-Result.json') -Encoding utf8
Write-Host '=== NUC 檢查結果 ===' -ForegroundColor Cyan
Write-Host ('SSH：'+$report.SSH.State+'；啟動方式：'+$report.SSH.StartMode)
Write-Host ('自動登入：'+$report.AutoLogon.DefaultUserName+'；啟用值：'+$report.AutoLogon.AutoAdminLogon)
Write-Host ('異常裝置數：'+$report.ProblemDevices.Count)
$report.Displays|Format-Table|Out-Host
$report.Disks|Format-Table|Out-Host
Write-Host ('Secure Boot：'+$report.SecureBoot)
Write-Host ('TPM 已就緒：'+$report.TPM.TpmReady)
Write-Host ('BitLocker 加密百分比：'+$report.BitLocker.EncryptionPercentage)
Write-Host ('需要重新開機：'+$report.RebootRequired)
Write-Host ('完整檢查結果：'+(Resolve-NucPath 'Audit-Result.json'))



