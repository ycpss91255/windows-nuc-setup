#Requires -Version 5.1
#Requires -RunAsAdministrator
$ErrorActionPreference='Stop'
& (Join-Path $PSScriptRoot 'Remove-OneDrive.ps1')
$apps=@(Get-Content (Join-Path $PSScriptRoot 'Debloat-Apps.txt')|Where-Object {$_ -and -not $_.StartsWith('#')})
$profile=Get-Content (Join-Path $PSScriptRoot 'Debloat-Profile.json') -Raw|ConvertFrom-Json
$before=@(Get-AppxPackage -AllUsers|Where-Object {@($_.PackageUserInformation|Where-Object InstallState -eq 'Installed').Count -gt 0}|Select-Object -ExpandProperty Name -Unique)
$log=Join-Path $PSScriptRoot ('Debloat-'+(Get-Date -Format yyyyMMdd-HHmmss)+'.log')
$argsList=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $PSScriptRoot 'Win11Debloat\Win11Debloat.ps1'),'-CLI','-Silent','-SkipExplorerRestart','-Language','zh-TW','-LogPath',$log,'-AppRemovalTarget','AllUsers','-RemoveApps','-Apps',($apps -join ','))
foreach($feature in $profile.Features){$argsList+=('-'+$feature)}
Write-Host ('正在執行 Win11Debloat，已選取 '+$apps.Count+' 個 App 項目及 '+$profile.Features.Count+' 項清理設定。') -ForegroundColor Cyan
& powershell.exe @argsList
$code=$LASTEXITCODE
$after=@(Get-AppxPackage -AllUsers|Where-Object {@($_.PackageUserInformation|Where-Object InstallState -eq 'Installed').Count -gt 0}|Select-Object -ExpandProperty Name -Unique)
$remaining=@($after|Where-Object {$_ -in $apps})
$provisioned=@(Get-AppxProvisionedPackage -Online|Where-Object DisplayName -in $apps|Select-Object -ExpandProperty DisplayName)
$result=[ordered]@{ProvisionedRemaining=$provisioned;BeforeAppCount=$before.Count;AfterAppCount=$after.Count;RemovedApps=@($before|Where-Object {$_ -notin $after});SelectedRemaining=$remaining;ExitCode=$code;Log=$log}
$result|ConvertTo-Json -Depth 5|Set-Content (Join-Path $PSScriptRoot 'Debloat-Result.json') -Encoding utf8
Write-Host ('本次實際移除：'+($result.RemovedApps -join ', '))
Write-Host ('清單中仍存在：'+($remaining -join ', '))
if($code -ne 0 -or $remaining.Count -or $provisioned.Count){throw '清理未完全成功，請查看 Debloat 紀錄及 Debloat-Result.json。'}
Write-Host 'Win11Debloat 清理完成。' -ForegroundColor Green



