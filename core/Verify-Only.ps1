#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')
Initialize-NucReports
$DriverPackagePath=Get-SetupSavedDriverSelection -ResultPath (Resolve-NucPath 'Setup-Result.json')
$hardware=Get-SetupHardwareProfile -DriverPackagePath $DriverPackagePath
$p=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
if(-not $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
 Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -NoExit -File "'+$PSCommandPath+'"');exit
}
$checks=New-Object Collections.Generic.List[object]
function Add-Check([string]$Name,[bool]$Passed,[string]$Detail){
 $checks.Add([pscustomobject]@{Name=$Name;Passed=$Passed;Status=$(if($Passed){'Passed'}else{'Failed'});Detail=$Detail})
 $label=if($Passed){'通過'}else{'未通過/待生效'}
 $color=if($Passed){'Green'}else{'Yellow'}
 Write-Host ('['+$label+'] '+$Name+'：'+$Detail) -ForegroundColor $color
}
Write-Host '=== Windows 可重複驗證（不安裝更新、不重新套用設定） ===' -ForegroundColor Cyan
try{ & (Resolve-NucPath 'Audit-NUC.ps1')|Out-Null }catch{Add-Check '基本硬體與帳號稽核' $false $_.Exception.Message}
$ssh=Get-CimInstance Win32_Service -Filter "Name='sshd'"
Add-Check 'SSH' ($ssh.State -eq 'Running' -and $ssh.StartMode -eq 'Auto') ($ssh.State+' / '+$ssh.StartMode)
try{ & (Resolve-NucPath 'Initialize-SSHClient.ps1') -VerifyOnly|Out-Null;Add-Check 'SSH 客戶端目錄' $true '目前使用者 .ssh/config、active-sites.conf、config.d 已存在' }catch{Add-Check 'SSH 客戶端目錄' $false $_.Exception.Message}
try{ & (Resolve-NucPath 'Apply-LANPingSettings.ps1') -VerifyOnly|Out-Null;Add-Check '同網段 IPv4/IPv6 Ping' $true 'LocalSubnet 入站回應規則啟用' }catch{Add-Check '同網段 IPv4/IPv6 Ping' $false $_.Exception.Message}
try{ & (Resolve-NucPath 'Apply-HostsSync.ps1') -VerifyOnly|Out-Null;Add-Check '依網路自動匯入框架' $true '各啟用輸出、目前帳號、背景程序及來源收斂均通過' }catch{Add-Check '依網路自動匯入框架' $false $_.Exception.Message}
$scope=@(Get-NetFirewallRule -Name OpenSSH-Server-In-TCP -ErrorAction SilentlyContinue|Get-NetFirewallAddressFilter|Select-Object -ExpandProperty RemoteAddress)
Add-Check 'SSH 防火牆範圍' ($scope -contains 'LocalSubnet') ($scope -join ', ')
foreach($setting in @('STANDBYIDLE','HIBERNATEIDLE')){
 $text=(& powercfg.exe /query SCHEME_CURRENT SUB_SLEEP $setting) -join "`n"
 $match=[regex]::Match($text,'(?im)^.*AC.*:\s*0x([0-9a-f]+)\s*$')
 $value=if($match.Success){[Convert]::ToInt64($match.Groups[1].Value,16)}else{-1}
 Add-Check ('插電 '+$setting) ($value -eq 0) ('秒數：'+$value+'；0 表示永不')
}
$auto=Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Add-Check '自動登入設定' ($auto.AutoAdminLogon -eq '1' -and  $auto.DefaultUserName -eq $env:USERNAME) ('啟用值：'+$auto.AutoAdminLogon+'；帳號：'+$auto.DefaultUserName+'；實際自動登入仍需開機觀察')
$driverDecision=Get-SetupModuleDecision -Module 'Install-Drivers.ps1' -Hardware $hardware
if(-not $driverDecision.Applicable){$checks.Add((New-SetupSkippedCheck -Name 'NUC 驅動封存檔' -Reason $driverDecision.Reason));Write-Host ('[略過] '+$driverDecision.Reason)}
else{try{$null=Test-SetupDriverPayload -Hardware $hardware -DriverPackagePath $DriverPackagePath;Add-Check 'NUC 驅動封存檔' $true '四個封存檔完整性通過'}catch{Add-Check 'NUC 驅動封存檔' $false $_.Exception.Message}}
$devices=@(Get-PnpDevice -PresentOnly|Where-Object Status -ne 'OK')
Add-Check '驅動裝置' ($devices.Count -eq 0) ('異常數：'+$devices.Count)
$search=Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search' -ErrorAction SilentlyContinue
Add-Check '搜尋欄隱藏原則' ($null -ne $search.SearchOnTaskbarMode -and $search.SearchOnTaskbarMode -eq 0) ('SearchOnTaskbarMode：'+$search.SearchOnTaskbarMode)
$widgets=Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Dsh' -ErrorAction SilentlyContinue
Add-Check '天氣/小工具關閉原則' ($null -ne $widgets.AllowNewsAndInterests -and $widgets.AllowNewsAndInterests -eq 0) ('AllowNewsAndInterests：'+$widgets.AllowNewsAndInterests)
$advanced=Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\explorer\Advanced' -ErrorAction SilentlyContinue
Add-Check '工作檢視按鈕隱藏' ($null -ne $advanced.ShowTaskViewButton -and $advanced.ShowTaskViewButton -eq 0) ('ShowTaskViewButton：'+$advanced.ShowTaskViewButton)
$layout=Join-Path $env:ProgramData 'NUC8-Setup\TaskbarLayout.xml'
$validLayout=$false
if(Test-Path $layout){[xml]$xml=Get-Content $layout -Raw;$pins=@($xml.SelectNodes('//*[local-name()="TaskbarPinList"]/*'));$validLayout=$pins.Count -eq 1 -and $pins[0].DesktopApplicationID -eq 'MSEdge'}
Add-Check 'Edge-only 釘選配置' $validLayout '檢查配置只有 MSEdge；實際圖示需在登入後查看'
$runOnce=Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -ErrorAction SilentlyContinue
$pendingPins=[bool]$runOnce.NUC8FinalizeTaskbar
Add-Check '釘選登入後套用' (-not $pendingPins) $(if($pendingPins){'仍待下次登入套用及解除暫時原則'}else{'沒有待執行的釘選收尾工作；請目視確認工作列'})
try{ & (Resolve-NucPath 'Apply-DisplaySettings.ps1') -VerifyOnly|Out-Null }catch{Write-Warning $_.Exception.Message}
$displayPath=Resolve-NucPath 'Display-Verification.json'
if(-not(Test-Path $displayPath)){$displayPath=Join-Path $env:ProgramData 'NUC8-Setup\Display-Verification.json'}
if(Test-Path $displayPath){$display=Get-Content $displayPath -Raw|ConvertFrom-Json;Add-Check '實際解析度與縮放' ([bool]$display.Success) ($display.Width.ToString()+'×'+$display.Height+' / '+$display.CurrentScalePercent+'%')}
else{Add-Check '實際解析度與縮放' $false '未取得桌面檢查結果'}
$desktopKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\explorer\HideDesktopIcons\NewStartPanel'
$icons=Get-ItemProperty $desktopKey -ErrorAction SilentlyContinue
$show=@('{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}','{20D04FE0-3AEA-1069-A2D8-08002B30309D}','{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}','{645FF040-5081-101B-9F08-00AA002F954E}')
$iconsOK=$true
foreach($id in $show){if($null -eq $icons.$id -or $icons.$id -ne 0){$iconsOK=$false}}
Add-Check '四個桌面系統圖示' $iconsOK '控制台、本機、網路、資源回收筒的顯示設定'
$desktopFiles=@(foreach($dir in @([Environment]::GetFolderPath('DesktopDirectory'),[Environment]::GetFolderPath('CommonDesktopDirectory'))){Get-ChildItem -LiteralPath $dir -Force -ErrorAction SilentlyContinue|Where-Object {-not ($_.Attributes -band [IO.FileAttributes]::Hidden) -and -not ($_.Attributes -band [IO.FileAttributes]::System)}|Select-Object -ExpandProperty Name})
Add-Check '桌面無其他一般檔案/捷徑' ($desktopFiles.Count -eq 0) ('剩餘項目：'+($desktopFiles -join ', '))
try{ & (Resolve-NucPath 'Apply-ThemeSettings.ps1') -VerifyOnly|Out-Null }catch{Write-Warning $_.Exception.Message}
$themePath=Resolve-NucPath 'Theme-Verification.json'
if(-not(Test-Path $themePath)){$themePath=Join-Path $env:ProgramData 'NUC8-Setup\Theme-Verification.json'}
if(Test-Path $themePath){$theme=Get-Content $themePath -Raw|ConvertFrom-Json;Add-Check '深色模式與純黑背景' ([bool]$theme.Success) ($theme.WindowsMode+' / '+$theme.AppsMode+' / 背景色值：'+$theme.ActualBackgroundColor)}else{Add-Check '深色模式與純黑背景' $false '未取得即時結果'}
$layoutDecision=Get-SetupModuleDecision -Module 'Desktop-IconLayout.ps1' -Hardware $hardware
if($layoutDecision.Applicable){
try{ & (Resolve-NucPath 'Desktop-IconLayout.ps1') -Mode Verify|Out-Null }catch{Write-Warning $_.Exception.Message}
$layoutResultPath=Resolve-NucPath 'IconLayout-Result.json'
if(-not(Test-Path $layoutResultPath)){$layoutResultPath=Join-Path $env:ProgramData 'NUC8-Setup\IconLayout-Result.json'}
if(Test-Path $layoutResultPath){$layoutResult=Get-Content $layoutResultPath -Raw|ConvertFrom-Json;Add-Check '四個圖示的實際排列座標' ([bool]$layoutResult.Success) $(if($layoutResult.Success){'目前座標與 Desktop-Layout.json 相符'}else{$layoutResult.Error})}else{Add-Check '四個圖示的實際排列座標' $false '未取得座標結果'}
}else{$checks.Add((New-SetupSkippedCheck -Name '四個圖示的實際排列座標' -Reason $layoutDecision.Reason));Write-Host ('[略過] '+$layoutDecision.Reason)}
$updatePath=Join-Path $env:ProgramData 'NUC8-Setup\WindowsUpdate\WindowsUpdate-Result.json'
if(Test-Path $updatePath){$updates=Get-Content $updatePath -Raw|ConvertFrom-Json;Add-Check '最近一次更新結果' (@($updates.Updates|Where-Object ResultCode -ne 2).Count -eq 0) ('完成時間：'+$updates.CompletedAt+'；安裝項目：'+$updates.Updates.Count)}
else{Add-Check '最近一次更新結果' $false '尚未找到本工具的更新結果'}
$reboot=(Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')
Add-Check '無待處理重新開機' (-not $reboot) $(if($reboot){'Windows 要求重新開機；目前不會自動重開'}else{'未偵測到待重新開機'})
$apps=Get-Content (Resolve-NucPath 'Debloat-Apps.txt')|Where-Object {$_ -and -not $_.StartsWith('#')}
$remaining=@(Get-AppxPackage -AllUsers|Where-Object {@($_.PackageUserInformation|Where-Object InstallState -eq 'Installed').Count -gt 0}|Where-Object Name -in $apps|Select-Object -ExpandProperty Name -Unique)
Add-Check '預載 App 清理' ($remaining.Count -eq 0) ('清單內仍存在：'+($remaining -join ', '))
try{ & (Resolve-NucPath 'Apply-PagefileSettings.ps1') -VerifyOnly|Out-Null }catch{Write-Warning $_.Exception.Message}
$page=Get-Content (Join-Path $env:ProgramData 'NUC8-Setup\Pagefile-Result.json') -Raw|ConvertFrom-Json
Add-Check '磁碟分頁檔停用設定' ([bool]$page.Success) ('RAM：'+$page.RAMGB+' GB；目前作用中：'+($page.ActivePagefiles -join ', '))
Add-Check '分頁檔實際已停用' (@($page.ActivePagefiles|Where-Object {$_}).Count -eq 0) '如仍作用中，需重新開機才生效'
try{ & (Resolve-NucPath 'Apply-CopilotSettings.ps1') -VerifyOnly|Out-Null;Add-Check '獨立版 Copilot 清理' $true '未安裝' }catch{Add-Check '獨立版 Copilot 清理' $false $_.Exception.Message}
$amdDecision=Get-SetupModuleDecision -Module 'Apply-AMDPrivacySettings.ps1' -Hardware $hardware
if($amdDecision.Applicable){
try{ & (Resolve-NucPath 'Apply-AMDPrivacySettings.ps1') -VerifyOnly|Out-Null;Add-Check 'AMD Software 位置權限' $true '已拒絕' }catch{Add-Check 'AMD Software 位置權限' $false $_.Exception.Message}
}else{$checks.Add((New-SetupSkippedCheck -Name 'AMD Software 位置權限' -Reason $amdDecision.Reason));Write-Host ('[略過] '+$amdDecision.Reason)}
try{ & (Resolve-NucPath 'Apply-StartMenuSettings.ps1') -VerifyOnly|Out-Null;Add-Check '開始選單釘選清空' $true '實際匯出清單為空' }catch{Add-Check '開始選單釘選清空' $false $_.Exception.Message}
try{ & (Resolve-NucPath 'Apply-InputMethodSettings.ps1') -VerifyOnly|Out-Null;Add-Check '英文美式鍵盤存在且為預設' $true 'en-US、0409:00000409 與預設輸入法均已確認' }catch{Add-Check '英文美式鍵盤存在且為預設' $false $_.Exception.Message}
try{ & (Resolve-NucPath 'Apply-TerminalHotkey.ps1') -VerifyOnly|Out-Null;Add-Check 'Terminal 全域快捷鍵' $true 'Ctrl+Alt+T 已註冊，監聽程序執行中' }catch{Add-Check 'Terminal 全域快捷鍵' $false $_.Exception.Message}
$explorer=Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\explorer\Advanced'
Add-Check '顯示一般隱藏檔案' ($explorer.Hidden -eq 1 -and $explorer.ShowSuperHidden -eq 0) '一般隱藏檔案顯示；受保護系統檔案隱藏'
try{ & (Resolve-NucPath 'Remove-SetupResidue.ps1') -VerifyOnly|Out-Null;Add-Check '空資料夾殘留清理' $true '實際資料不會刪除，詳見 Residue-Result.json' }catch{Add-Check '空資料夾殘留清理' $false $_.Exception.Message}
try{ & (Resolve-NucPath 'Remove-OneDrive.ps1') -VerifyOnly|Out-Null;Add-Check 'OneDrive 解除安裝' $true '程式未安裝且未執行；資料檔保留' }catch{Add-Check 'OneDrive 解除安裝' $false $_.Exception.Message}
try{ & (Resolve-NucPath 'Apply-ExplorerSettings.ps1') -VerifyOnly|Out-Null;Add-Check '檔案總管隱藏檔即時狀態' $true 'Shell 狀態與登錄值均為顯示' }catch{Add-Check '檔案總管隱藏檔即時狀態' $false $_.Exception.Message}
$provisioned=@(Get-AppxProvisionedPackage -Online|Where-Object DisplayName -in $apps|Select-Object -ExpandProperty DisplayName)
Add-Check '新帳號預載 App 清理' ($provisioned.Count -eq 0) ($provisioned -join ', ')
$result=[ordered]@{Computer=$env:COMPUTERNAME;VerifiedAt=(Get-Date).ToString('o');HardwareProfile=$hardware;SkippedCount=@($checks|Where-Object Status -eq Skipped).Count;Passed=(Test-SetupChecksPassed -Checks @($checks.ToArray()));Checks=@($checks.ToArray());Notes=@('本工具只驗證，不安裝更新或重新套用偏好。','自動登入是否真的成功，以及工作列實際圖示，仍需在下次登入後觀察。','Windows 啟用由使用者另外處理。')}
$result|ConvertTo-Json -Depth 6|Set-Content (Resolve-NucPath 'Verification-Result.json') -Encoding UTF8
Write-Host ('驗證紀錄：'+(Resolve-NucPath 'Verification-Result.json'))













