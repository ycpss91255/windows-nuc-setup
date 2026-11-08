#Requires -Version 5.1
param([switch]$PackageOnly,[ValidateSet('Auto','Generic','NUC8')][string]$HardwareProfile='Auto',[string]$DriverPackagePath,[string]$ConfirmedBoard,[string]$ConfirmationComputer)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'paths.ps1')
foreach($entry in @('init.cmd','windows.cmd','readme.md')){if(-not(Test-Path -LiteralPath (Join-Path $script:NucPackageRoot $entry) -PathType Leaf)){throw ('缺少根目錄入口或說明：'+$entry)}}
$config=[IO.File]::ReadAllText((Resolve-NucPath 'configuration_library.ps1'))
$modules=@('apply_autologon_settings.ps1')+@([regex]::Matches($config,"File='([^']+\.ps1)'" )|ForEach-Object {$_.Groups[1].Value})
if($modules.Count -ne 19 -or @($modules|Select-Object -Unique).Count -ne 19){throw '模組清單不是 19 個不重複項目。'}
$required=$modules+@('paths.ps1','verification.ps1','paths.json','start_windows.ps1','initialize_nuc.ps1','oobe_library.ps1','cleanup_oobe.ps1','run_module.ps1','Autologon64.exe','finalize_taskbar.ps1','desktop_layout.json','desktop_safety.ps1','terminal_hotkey_listener.ps1','remove_one_drive.ps1','initialize_ssh_client.ps1','ssh_firewall.ps1','apply_lan_ping_settings.ps1','apply_hosts_sync.ps1','CustomHostsSync\network_sites.ps1','CustomHostsSync\sync_custom_hosts.ps1','CustomHostsSync\watch_custom_hosts.ps1','CustomHostsSync\sites.json','CustomHostsSync\hosts_readme.md','CustomHostsSync\ssh_readme.md','debloat_apps.txt','debloat_profile.json','win11debloat\Win11Debloat.ps1','verify_only.ps1','audit_nuc.ps1')
$required+=@('start_pins_policy_library.ps1','start_pins_asset_library.ps1','provisioning_library.ps1','provisioning_asset_library.ps1','provisioning_launcher_library.ps1')
$required+=@('amd_privacy_library.ps1','driver_archive_library.ps1','driver_plan_library.ps1','driver_installation_library.ps1','gui_stage_library.ps1','gui_worker.ps1','explorer_settings_library.ps1','display_settings_library.ps1','theme_settings_library.ps1','desktop_settings_library.ps1','icons_settings_library.ps1','after_restart_library.ps1','configuration_library.ps1','terminal_hotkey_library.ps1','one_drive_library.ps1','update_stage_library.ps1','update_progress_library.ps1','update_worker_library.ps1','update_callback.cs','uac_library.ps1','apply_uac_settings.ps1','apply_uac_settings.cmd','managed_source_library.ps1','desktop_icons.cs','display.cs','explorer.cs','theme.cs','terminal_hotkey.cs','residue_library.ps1','hosts_sync_library.ps1','connection_info_library.ps1','verification_library.ps1','privacy_library.ps1','input_method_library.ps1','audit_library.ps1','init_entry_library.ps1','apply_privacy_settings.ps1','apply_privacy_settings.cmd')
foreach($file in $required){if(-not(Test-Path -LiteralPath (Resolve-NucPath $file) -PathType Leaf)){throw ('缺少工具包檔案：'+$file)}}
# Source validation is safe on Server and never calls the client provisioning API.
. (Resolve-NucPath 'start_pins_asset_library.ps1')
$null=Assert-StartPinsAssetSource -AssetRoot (Join-Path $script:NucPackageRoot 'modules/start_menu/assets')
. (Resolve-NucPath 'provisioning_asset_library.ps1')
$null=Assert-InitProvisioningAssetSource -AssetRoot (Join-Path $script:NucPackageRoot 'modules/init/assets')
$scriptFiles=@(Get-ChildItem -LiteralPath (Join-Path $script:NucPackageRoot 'core') -Filter '*.ps1')+@(Get-ChildItem -LiteralPath (Join-Path $script:NucPackageRoot 'modules') -Recurse -Filter '*.ps1'|Where-Object {$_.FullName -notmatch '[\/]Win11Debloat[\/]'})
foreach($file in $scriptFiles){
 $tokens=$null;$errors=$null
 [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
 if($errors.Count){throw ('腳本語法錯誤：'+$file.Name+'；'+$errors[0].Message)}
}
if(-not $PackageOnly -and $HardwareProfile -ne 'Auto'){throw '硬體設定檔覆寫只可用於 PackageOnly 離線檢查。'}
$hardware=if($HardwareProfile -eq 'NUC8'){Get-SetupHardwareProfile -BoardProduct 'NUC8i7HVB'}elseif($HardwareProfile -eq 'Generic'){Get-SetupHardwareProfile -BoardProduct 'Generic'}else{Get-SetupHardwareProfile -ConfirmedBoard $ConfirmedBoard -ConfirmationComputer $ConfirmationComputer}
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
 . (Resolve-NucPath 'desktop_safety.ps1')
 Assert-DesktopSourceLocation -SourceRoot $script:NucPackageRoot -DesktopRoots @([Environment]::GetFolderPath('DesktopDirectory'),[Environment]::GetFolderPath('CommonDesktopDirectory'))
}
Write-Host ('前置檢查通過：19 個模組、必要檔案及 '+$payload.Count+' 個驅動封存檔；帳號及路徑動態取得。') -ForegroundColor Green




