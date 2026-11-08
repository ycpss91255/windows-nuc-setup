#Requires -Version 5.1
param([string]$UserName=$env:USERNAME,[string]$AutoLogonPassword,[string]$DriverPackagePath,[string]$ExpectedUserSID,[string]$ConfirmedBoard,[string]$ConfirmationComputer)
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
    Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -EncodedCommand '+[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command)))
    exit
}
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'modules\init\provisioning_library.ps1')
$null=Invoke-InitWindowsCheckpoint -StageRoot (Join-Path $env:ProgramData 'windows_setup_init')
& (Resolve-NucPath 'test_setup_prerequisites.ps1') -DriverPackagePath $DriverPackagePath -ConfirmedBoard $ConfirmedBoard -ConfirmationComputer $ConfirmationComputer
if($hardware.IsNuc8 -and $DriverPackagePath){$hardware|Add-Member -NotePropertyName DriverSelection -NotePropertyValue (New-SetupDriverSelection -PackageRoot $script:NucPackageRoot -DriverPackagePath $DriverPackagePath) -Force}
if($UserName -ine $env:USERNAME){throw '自動登入帳號必須與目前執行帳號相同。'}
$log=Resolve-NucPath ('Setup-'+(Get-Date -Format yyyyMMdd-HHmmss)+'.log')
Start-Transcript -Path $log | Out-Null
try {
    Write-Host '[1/19] 設定開機自動登入' -ForegroundColor Cyan
    Write-Progress -Id 1 -Activity 'Windows 一鍵設定' -Status '[1/19] 自動登入' -PercentComplete 0
    & (Resolve-NucPath 'apply_autologon_settings.ps1') -UserName $UserName -AutoLogonPassword $AutoLogonPassword
    $AutoLogonPassword=$null
    $auto=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $stageErrors=@();$failedModules=@()
    $stageIndex=1
    foreach($stage in @(
        @{Name='停用磁碟分頁檔';File='apply_pagefile_settings.ps1'},
        @{Name='插電時停用自動睡眠/休眠';File='apply_power_settings.ps1'},
        @{Name='SSH 服務與區域網路防火牆';File='apply_ssh_settings.ps1'},
        @{Name='缺少驅動';File='install_drivers.ps1'},
        @{Name='拒絕 AMD Software 位置存取';File='apply_amd_privacy_settings.ps1'},
        @{Name='Windows Update 建議更新';File='install_windows_updates.ps1'},
        @{Name='Win11Debloat 清理';File='apply_debloat.ps1'},
        @{Name='獨立版 Copilot 清理';File='apply_copilot_settings.ps1'},
        @{Name='工作列天氣/搜尋/Edge 釘選';File='apply_taskbar_settings.ps1'},
        @{Name='清空開始選單釘選及關閉推薦';File='apply_start_menu_settings.ps1'},
        @{Name='1920×1080 與 100% 縮放';File='apply_display_settings.ps1'},
        @{Name='清空一般桌面項目，僅顯示四個系統圖示';File='apply_desktop_settings.ps1'},
        @{Name='深色模式與純黑背景';File='apply_theme_settings.ps1'},
        @{Name='預設英文美式鍵盤';File='apply_input_method_settings.ps1'},
        @{Name='Ctrl+Alt+T 開啟 Terminal';File='apply_terminal_hotkey.ps1'},
        @{Name='顯示隱藏檔案';File='apply_explorer_settings.ps1'},
        @{Name='清除空的舊系統及預設使用者資料夾';File='remove_setup_residue.ps1'},
        @{Name='套用指定桌面圖示排列';File='desktop_icon_layout.ps1'}
    )){
        $stageIndex++
        Write-Host ('['+$stageIndex+'/19] '+$stage.Name) -ForegroundColor Cyan
        Write-Progress -Id 1 -Activity 'Windows 一鍵設定' -Status ('['+$stageIndex+'/19] '+$stage.Name) -PercentComplete ([int](100*($stageIndex-1)/19))
        @{Step=$stageIndex;Total=19;Stage=$stage.Name;UpdatedAt=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content (Resolve-NucPath 'Setup-Progress.json') -Encoding UTF8
        $decision=Get-SetupModuleDecision -Module $stage.File -Hardware $hardware
        if(-not $decision.Applicable){$skippedModules+=$decision;Write-Host ('[略過] '+$stage.Name+'：'+$decision.Reason) -ForegroundColor Yellow;continue}
        try { if($stage.File -eq 'install_drivers.ps1'){& (Resolve-NucPath $stage.File) -NonInteractive -DriverPackagePath $DriverPackagePath -ConfirmedBoard $ConfirmedBoard -ConfirmationComputer $ConfirmationComputer}else{& (Resolve-NucPath $stage.File)} }
        catch { $failedModules+=$stage.File;$stageErrors+=($stage.Name+'：'+$_.Exception.Message);Write-Warning $stageErrors[-1] }
    }
    $problems=@(Get-PnpDevice -PresentOnly|Where-Object Status -ne 'OK')
    try{ & (Resolve-NucPath 'audit_nuc.ps1') }catch{ $stageErrors+=('最終檢查：'+$_.Exception.Message);Write-Warning $stageErrors[-1] }
    $summary=[ordered]@{Success=($stageErrors.Count -eq 0 -and $problems.Count -eq 0);Computer=$env:COMPUTERNAME;CompletedAt=(Get-Date).ToString('o');AutoLogonUser=$auto.DefaultUserName;AutoLogonEnabled=($auto.AutoAdminLogon -eq '1');RequiresNextSignIn=$true;ProblemDeviceCount=$problems.Count;StageErrors=$stageErrors;FailedModules=$failedModules;HardwareProfile=$hardware;SkippedModules=$skippedModules;UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;RebootRequired=((Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'))}
    $summary|ConvertTo-Json -Depth 5|Set-Content (Resolve-NucPath 'Setup-Result.json') -Encoding UTF8
    Write-Progress -Id 1 -Activity 'Windows 一鍵設定' -Completed
    @{Step=19;Total=19;Stage='本輪執行結束';HasErrors=($stageErrors.Count -gt 0 -or $problems.Count -gt 0);UpdatedAt=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content (Resolve-NucPath 'Setup-Progress.json') -Encoding UTF8

    Write-Host ('目前異常裝置數：'+$problems.Count)
    if($stageErrors.Count -or $problems.Count){throw '部分步驟或裝置檢查未完成，已寫入 Setup-Result.json 與 Setup-Progress.json；請查看紀錄後重試。'}
    else{Write-Host '本輪一鍵設定完成。' -ForegroundColor Green}
    Write-Host '請手動重新開機，再執行 windows.cmd -AfterRestart 檢查及繼續更新。'
} finally { $AutoLogonPassword=$null; Stop-Transcript | Out-Null }













