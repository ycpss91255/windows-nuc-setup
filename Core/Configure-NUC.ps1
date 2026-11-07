#Requires -Version 5.1
param([string]$UserName=$env:USERNAME,[string]$AutoLogonPassword)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')
Initialize-NucReports
$principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -File "'+$PSCommandPath+'"')
    exit
}
& (Resolve-NucPath 'Test-SetupPrerequisites.ps1')
if($UserName -ine $env:USERNAME){throw '自動登入帳號必須與目前執行帳號相同。'}
$log=Resolve-NucPath ('Setup-'+(Get-Date -Format yyyyMMdd-HHmmss)+'.log')
Start-Transcript -Path $log | Out-Null
try {
    Write-Host '[1/19] 設定開機自動登入' -ForegroundColor Cyan
    Write-Progress -Id 1 -Activity 'NUC 一鍵設定' -Status '[1/19] 自動登入' -PercentComplete 0
    & (Resolve-NucPath 'Apply-AutologonSettings.ps1') -UserName $UserName -AutoLogonPassword $AutoLogonPassword
    $AutoLogonPassword=$null
    $auto=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    $stageErrors=@();$failedModules=@()
    $stageIndex=1
    foreach($stage in @(
        @{Name='停用磁碟分頁檔';File='Apply-PagefileSettings.ps1'},
        @{Name='插電時停用自動睡眠/休眠';File='Apply-PowerSettings.ps1'},
        @{Name='SSH 服務與區域網路防火牆';File='Apply-SSHSettings.ps1'},
        @{Name='缺少驅動';File='Install-Drivers.ps1'},
        @{Name='拒絕 AMD Software 位置存取';File='Apply-AMDPrivacySettings.ps1'},
        @{Name='Windows Update 建議更新';File='Install-WindowsUpdates.ps1'},
        @{Name='Win11Debloat 清理';File='Apply-Debloat.ps1'},
        @{Name='獨立版 Copilot 清理';File='Apply-CopilotSettings.ps1'},
        @{Name='工作列天氣/搜尋/Edge 釘選';File='Apply-TaskbarSettings.ps1'},
        @{Name='清空開始選單釘選及關閉推薦';File='Apply-StartMenuSettings.ps1'},
        @{Name='1920×1080 與 100% 縮放';File='Apply-DisplaySettings.ps1'},
        @{Name='清空一般桌面項目，僅顯示四個系統圖示';File='Apply-DesktopSettings.ps1'},
        @{Name='深色模式與純黑背景';File='Apply-ThemeSettings.ps1'},
        @{Name='預設英文美式鍵盤';File='Apply-InputMethodSettings.ps1'},
        @{Name='Ctrl+Alt+T 開啟 Terminal';File='Apply-TerminalHotkey.ps1'},
        @{Name='顯示隱藏檔案';File='Apply-ExplorerSettings.ps1'},
        @{Name='清除空的舊系統及預設使用者資料夾';File='Remove-SetupResidue.ps1'},
        @{Name='套用指定桌面圖示排列';File='Desktop-IconLayout.ps1'}
    )){
        $stageIndex++
        Write-Host ('['+$stageIndex+'/19] '+$stage.Name) -ForegroundColor Cyan
        Write-Progress -Id 1 -Activity 'NUC 一鍵設定' -Status ('['+$stageIndex+'/19] '+$stage.Name) -PercentComplete ([int](100*($stageIndex-1)/19))
        @{Step=$stageIndex;Total=19;Stage=$stage.Name;UpdatedAt=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content (Resolve-NucPath 'Setup-Progress.json') -Encoding UTF8
        try { & (Resolve-NucPath $stage.File) }
        catch { $failedModules+=$stage.File;$stageErrors+=($stage.Name+'：'+$_.Exception.Message);Write-Warning $stageErrors[-1] }
    }
    $problems=@(Get-PnpDevice -PresentOnly|Where-Object Status -ne 'OK')
    try{ & (Resolve-NucPath 'Audit-NUC.ps1') }catch{ $stageErrors+=('最終檢查：'+$_.Exception.Message);Write-Warning $stageErrors[-1] }
    $summary=[ordered]@{Computer=$env:COMPUTERNAME;CompletedAt=(Get-Date).ToString('o');AutoLogonUser=$auto.DefaultUserName;AutoLogonEnabled=($auto.AutoAdminLogon -eq '1');RequiresNextSignIn=$true;ProblemDeviceCount=$problems.Count;StageErrors=$stageErrors;FailedModules=$failedModules;UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;RebootRequired=((Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'))}
    $summary|ConvertTo-Json -Depth 5|Set-Content (Resolve-NucPath 'Setup-Result.json') -Encoding UTF8
    Write-Progress -Id 1 -Activity 'NUC 一鍵設定' -Completed
    @{Step=19;Total=19;Stage='本輪執行結束';HasErrors=($stageErrors.Count -gt 0);UpdatedAt=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content (Resolve-NucPath 'Setup-Progress.json') -Encoding UTF8

    Write-Host ('目前異常裝置數：'+$problems.Count)
    if($stageErrors.Count -or $problems.Count){Write-Warning '部分步驟未完成，請查看 Setup-Result.json 與各步驟紀錄。'}
    else{Write-Host '本輪一鍵設定完成。' -ForegroundColor Green}
    Write-Host '請手動重新開機，再執行 Windows.cmd -AfterRestart 檢查及繼續更新。'
} finally { $AutoLogonPassword=$null; Stop-Transcript | Out-Null }













