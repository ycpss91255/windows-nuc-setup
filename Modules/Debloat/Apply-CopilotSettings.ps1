#Requires -RunAsAdministrator
param([switch]$VerifyOnly)
$ErrorActionPreference='Stop'
function Find-Copilot { @(Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue|Where-Object {$_.DisplayName -eq 'Copilot' -and $_.Publisher -eq 'Microsoft Corporation'}) }
$before=@(Find-Copilot)
$exitCode=$null
if(-not $VerifyOnly -and $before.Count){
 Write-Host '正在移除獨立版 Microsoft Copilot…' -ForegroundColor Cyan
 & winget.exe uninstall --name Copilot --exact --source winget --silent --disable-interactivity
 $exitCode=$LASTEXITCODE
 Start-Sleep -Seconds 3
}
$remaining=@(Find-Copilot)
$root=Join-Path $env:ProgramData 'NUC8-Setup'
New-Item -ItemType Directory $root -Force|Out-Null
$result=[ordered]@{Success=($remaining.Count -eq 0);RemainingCount=$remaining.Count;UninstallerExitCode=$exitCode;CheckedAt=(Get-Date).ToString('o')}
$result|ConvertTo-Json|Set-Content (Join-Path $root 'Copilot-Result.json') -Encoding UTF8
if(-not $result.Success){throw '獨立版 Copilot 仍存在，請檢查卸載紀錄。'}
Write-Host '已確認獨立版 Copilot 不存在。' -ForegroundColor Green
