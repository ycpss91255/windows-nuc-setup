#Requires -Version 5.1
param([switch]$PackageOnly,[ValidateSet('Auto','Generic','NUC8')][string]$HardwareProfile='Auto',[string]$DriverPackagePath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')
foreach($entry in @('Init.cmd','Windows.cmd','README.md')){if(-not(Test-Path -LiteralPath (Join-Path $script:NucPackageRoot $entry) -PathType Leaf)){throw ('缺少根目錄入口或說明：'+$entry)}}
$config=[IO.File]::ReadAllText((Resolve-NucPath 'Configure-NUC.ps1'))
$modules=@('Apply-AutologonSettings.ps1')+@([regex]::Matches($config,"File='([^']+\.ps1)'" )|ForEach-Object {$_.Groups[1].Value})
if($modules.Count -ne 19 -or @($modules|Select-Object -Unique).Count -ne 19){throw '模組清單不是 19 個不重複項目。'}
$required=$modules+@('Paths.ps1','Verification.ps1','Paths.json','Start-Windows.ps1','Initialize-NUC.ps1','OOBE-Library.ps1','Cleanup-OOBE.ps1','Run-Module.ps1','Autologon64.exe','Finalize-Taskbar.ps1','Desktop-Layout.json','Terminal-HotkeyListener.ps1','Remove-OneDrive.ps1','Initialize-SSHClient.ps1','Apply-LANPingSettings.ps1','Apply-HostsSync.ps1','CustomHostsSync\network-sites.ps1','CustomHostsSync\sync-custom-hosts.ps1','CustomHostsSync\watch-custom-hosts.ps1','CustomHostsSync\sites.json','CustomHostsSync\Hosts-README.md','CustomHostsSync\SSH-README.md','Debloat-Apps.txt','Debloat-Profile.json','win11debloat\Win11Debloat.ps1','Verify-Only.ps1','Audit-NUC.ps1')
foreach($file in $required){if(-not(Test-Path -LiteralPath (Resolve-NucPath $file) -PathType Leaf)){throw ('缺少工具包檔案：'+$file)}}
$scriptFiles=@(Get-ChildItem -LiteralPath (Join-Path $script:NucPackageRoot 'core') -Filter '*.ps1')+@(Get-ChildItem -LiteralPath (Join-Path $script:NucPackageRoot 'modules') -Recurse -Filter '*.ps1'|Where-Object {$_.FullName -notmatch '[\/]Win11Debloat[\/]'})
foreach($file in $scriptFiles){
 $tokens=$null;$errors=$null
 [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
 if($errors.Count){throw ('腳本語法錯誤：'+$file.Name+'；'+$errors[0].Message)}
}
if(-not $PackageOnly -and $HardwareProfile -ne 'Auto'){throw '硬體設定檔覆寫只可用於 PackageOnly 離線檢查。'}
$hardware=if($HardwareProfile -eq 'NUC8'){Get-SetupHardwareProfile -BoardProduct 'NUC8i7HVB'}elseif($HardwareProfile -eq 'Generic'){Get-SetupHardwareProfile -BoardProduct 'Generic'}else{Get-SetupHardwareProfile}
$payload=Test-SetupDriverPayload -Hardware $hardware -DriverPackagePath $DriverPackagePath
Write-Host ('硬體設定檔：'+$hardware.Name+'；'+$payload.Reason)
if(-not $PackageOnly){
 if(-not [Environment]::Is64BitProcess){throw '請用 64 位元 Windows PowerShell 執行。'}
 $os=Get-CimInstance Win32_OperatingSystem
 if([int]$os.BuildNumber -lt 22621){throw '需要 Windows 11 22H2 或更新版本。'}
 $edition=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
 if($edition -notmatch 'Professional|Enterprise|Education'){throw ('此套偏好原則需要 Windows 專業版或企業/教育版，目前：'+$edition)}
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 if($identity.User.Value -eq 'S-1-5-18' -or $identity.User.Value -match '-500$'){throw 'Windows 流程不可在 SYSTEM 或稽核用內建 Administrator 執行；請先用 Init 建立正式帳號並登入。'}
 $imageState=(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\State' -ErrorAction Stop).ImageState
 if($imageState -ne 'IMAGE_STATE_COMPLETE'){throw 'Windows 初始設定尚未完成；請完成 Init／OOBE 並登入正式帳號後再執行 Windows。'}
 $local=Get-LocalUser -SID $identity.User -ErrorAction Stop
 if(-not $local.Enabled){throw '目前本機帳號未啟用。'}
 $session=[Diagnostics.Process]::GetCurrentProcess().SessionId
 $explorers=@(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'"|Where-Object {$session -eq 0 -or $_.SessionId -eq $session})
 $owners=@($explorers|ForEach-Object {(Invoke-CimMethod -InputObject $_ -MethodName GetOwnerSid).Sid})
 if($identity.User.Value -notin $owners){throw '請以目前登入桌面的本機管理員帳號執行，不可用另一個管理員帳號提權。'}
 foreach($cmd in @('wt.exe','winget.exe')){if(-not(Get-Command $cmd -ErrorAction SilentlyContinue)){throw ('缺少 '+$cmd+'；請先安裝 Windows Terminal / App Installer。')}}
 foreach($desktop in @([Environment]::GetFolderPath('DesktopDirectory'),[Environment]::GetFolderPath('CommonDesktopDirectory'))){
  if([IO.Path]::GetFullPath($script:NucPackageRoot).StartsWith($desktop.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase)){throw '工具包不可放在桌面內執行，因流程會清理桌面。請從 USB 或 Downloads 執行。'}
 }
}
Write-Host ('前置檢查通過：19 個模組、必要檔案及 '+$payload.Count+' 個驅動封存檔；帳號及路徑動態取得。') -ForegroundColor Green




