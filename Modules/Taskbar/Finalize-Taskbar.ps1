#Requires -Version 5.1
# 在登入後讓 Explorer 先載入工作列配置，再解除暫時的 Start Layout 原則。
Start-Sleep -Seconds 45
$policy='HKCU:\Software\Policies\Microsoft\Windows\Explorer'
$expected=Join-Path $env:ProgramData 'NUC8-Setup\TaskbarLayout.xml'
$current=Get-ItemProperty $policy -ErrorAction SilentlyContinue
if($current.StartLayoutFile -eq $expected){
 Remove-ItemProperty $policy -Name LockedStartLayout -ErrorAction SilentlyContinue
 Remove-ItemProperty $policy -Name StartLayoutFile -ErrorAction SilentlyContinue
 $dir=Join-Path $env:LOCALAPPDATA 'NUC8-Setup'
 New-Item -ItemType Directory $dir -Force|Out-Null
 @{FinalizedAt=(Get-Date).ToString('o');TemporaryLayoutPolicyRemoved=$true}|ConvertTo-Json|Set-Content (Join-Path $dir 'Taskbar-Finalize.json') -Encoding UTF8
}