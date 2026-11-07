#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$Worker)
$ErrorActionPreference='Stop'
$root=Join-Path $env:ProgramData 'NUC8-Setup'
New-Item -ItemType Directory -Path $root -Force|Out-Null
if(-not $Worker -and [Diagnostics.Process]::GetCurrentProcess().SessionId -eq 0){
 $workerPath=Join-Path $root 'Taskbar-Worker.ps1'
 Copy-Item -LiteralPath $PSCommandPath -Destination $workerPath -Force
 Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Finalize-Taskbar.ps1') -Destination (Join-Path $root 'Taskbar-Finalize-Source.ps1') -Force
 $resultPath=Join-Path $root 'Taskbar-Result.json'
 if(Test-Path $resultPath){Move-Item -LiteralPath $resultPath -Destination (Join-Path $root ('Taskbar-Previous-'+(Get-Date -Format yyyyMMdd-HHmmss)+'.json')) -Force}
 $name='NUC8-Apply-Taskbar'
 $action=New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$workerPath+'" -Worker')
 $principal=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Highest
 Register-ScheduledTask -TaskName $name -Action $action -Principal $principal -Force|Out-Null
 Start-ScheduledTask -TaskName $name
 Write-Host '正在目前登入的桌面套用工作列設定…' -ForegroundColor Cyan
 $deadline=(Get-Date).AddSeconds(60)
 do{Start-Sleep -Seconds 2;$task=Get-ScheduledTask -TaskName $name;if(Test-Path $resultPath){break}}while((Get-Date) -lt $deadline)
 $info=Get-ScheduledTaskInfo -TaskName $name
 if($task.State -ne 'Running'){Unregister-ScheduledTask -TaskName $name -Confirm:$false}
 if(-not(Test-Path $resultPath)){throw ('未取得桌面工作列設定結果；請在目標電腦登入桌面後再次執行。工作結果：'+$info.LastTaskResult)}
 $result=Get-Content $resultPath -Raw|ConvertFrom-Json
 if($resultPath -ne (Join-Path $PSScriptRoot 'Taskbar-Result.json')){Copy-Item $resultPath (Join-Path $PSScriptRoot 'Taskbar-Result.json') -Force}
 $result|Format-List|Out-Host
 if(-not $result.Success){throw $result.Error}
 return
}
try{
$backup=Join-Path $PSScriptRoot ('Taskbar-Before-'+(Get-Date -Format yyyyMMdd-HHmmss)+'.reg')
& reg.exe export 'HKCU\Software\Microsoft\Windows\CurrentVersion\explorer\Advanced' $backup /y | Out-Null
$search='HKCU:\Software\Microsoft\Windows\CurrentVersion\Search'
$advanced='HKCU:\Software\Microsoft\Windows\CurrentVersion\explorer\Advanced'
if(-not(Test-Path $search)){New-Item $search -Force|Out-Null}
$searchPolicy='HKLM:\SOFTWARE\Policies\Microsoft\Windows\Windows Search'
if(-not(Test-Path $searchPolicy)){New-Item $searchPolicy -Force|Out-Null}
New-ItemProperty $searchPolicy -Name SearchOnTaskbarMode -Value 0 -PropertyType DWord -Force|Out-Null
try{New-ItemProperty $advanced -Name TaskbarDa -Value 0 -PropertyType DWord -Force|Out-Null}catch{Write-Warning '個人小工具開關受保護，將以機器原則關閉小工具。'}
New-ItemProperty $advanced -Name ShowTaskViewButton -Value 0 -PropertyType DWord -Force|Out-Null
$widgets='HKLM:\SOFTWARE\Policies\Microsoft\Dsh'
if(-not(Test-Path $widgets)){New-Item $widgets -Force|Out-Null}
New-ItemProperty $widgets -Name AllowNewsAndInterests -Value 0 -PropertyType DWord -Force|Out-Null
$layoutPath=Join-Path $root 'TaskbarLayout.xml'
$xml=@"
<?xml version="1.0" encoding="utf-8"?>
<LayoutModificationTemplate xmlns="http://schemas.microsoft.com/Start/2014/LayoutModification" xmlns:defaultlayout="http://schemas.microsoft.com/Start/2014/FullDefaultLayout" xmlns:start="http://schemas.microsoft.com/Start/2014/StartLayout" xmlns:taskbar="http://schemas.microsoft.com/Start/2014/TaskbarLayout" Version="1">
  <CustomTaskbarLayoutCollection PinListPlacement="Replace">
    <defaultlayout:TaskbarLayout>
      <taskbar:TaskbarPinList>
        <taskbar:DesktopApp DesktopApplicationID="MSEdge" />
      </taskbar:TaskbarPinList>
    </defaultlayout:TaskbarLayout>
  </CustomTaskbarLayoutCollection>
</LayoutModificationTemplate>
"@
[xml]$validated=$xml
[IO.File]::WriteAllText($layoutPath,$xml,[Text.UTF8Encoding]::new($false))
$policy='HKCU:\Software\Policies\Microsoft\Windows\Explorer'
if(-not(Test-Path $policy)){New-Item $policy -Force|Out-Null}
New-ItemProperty $policy -Name StartLayoutFile -Value $layoutPath -PropertyType String -Force|Out-Null
New-ItemProperty $policy -Name LockedStartLayout -Value 1 -PropertyType DWord -Force|Out-Null
# 原則只用來套用釘選配置，登入後解除，避免長期限制開始功能表的自訂。
$cleanupPath=Join-Path $root 'Finalize-Taskbar.ps1'
if($Worker){Copy-Item -LiteralPath (Join-Path $root 'Taskbar-Finalize-Source.ps1') -Destination $cleanupPath -Force}elseif((Join-Path $PSScriptRoot 'Finalize-Taskbar.ps1') -ne $cleanupPath){Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Finalize-Taskbar.ps1') -Destination $cleanupPath -Force}
$runOnce='HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
if(-not(Test-Path $runOnce)){New-Item $runOnce -Force|Out-Null}
$command='powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "'+$cleanupPath+'"'
New-ItemProperty $runOnce -Name NUC8FinalizeTaskbar -Value $command -PropertyType String -Force|Out-Null
$result=[ordered]@{Success=$true;SearchPolicyMode=(Get-ItemProperty $searchPolicy).SearchOnTaskbarMode;TaskbarDa=(Get-ItemProperty $advanced).TaskbarDa;WidgetsPolicy=(Get-ItemProperty $widgets).AllowNewsAndInterests;ShowTaskViewButton=(Get-ItemProperty $advanced).ShowTaskViewButton;TaskbarLayout=$layoutPath;PinnedDesktopApp='MSEdge';RequiresNextSignIn=$true;AppliedAt=(Get-Date).ToString('o')}
$result|ConvertTo-Json|Set-Content (Join-Path $PSScriptRoot 'Taskbar-Result.json') -Encoding UTF8
Write-Host '工作列設定已寫入：天氣/小工具關閉、搜尋欄隱藏、預設釘選只保留 Edge。' -ForegroundColor Green
Write-Host '按 Windows 鍵直接輸入搜尋仍可使用。釘選配置在下次登入時套用；本工具不會自動登出或重新開機。'
}catch{
 @{Success=$false;Error=$_.Exception.Message;FailedAt=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $root 'Taskbar-Result.json') -Encoding UTF8
 throw
}