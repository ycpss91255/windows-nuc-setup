#Requires -RunAsAdministrator
param([switch]$VerifyOnly,[ValidatePattern('^[a-fA-F0-9-]{36}$')][string]$VerificationRunId)
$ErrorActionPreference='Stop'
$root=Join-Path $env:ProgramData 'NUC8-Setup'
New-Item -ItemType Directory $root -Force|Out-Null
if(-not $VerifyOnly){
 Get-CimInstance Win32_ComputerSystem|Set-CimInstance -Property @{AutomaticManagedPagefile=$false}|Out-Null
 Get-CimInstance Win32_PageFileSetting|Remove-CimInstance
 New-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -Name PagingFiles -PropertyType MultiString -Value @() -Force|Out-Null
}
$system=Get-CimInstance Win32_ComputerSystem
$settings=@(Get-CimInstance Win32_PageFileSetting)
$usage=@(Get-CimInstance Win32_PageFileUsage)
$paging=@((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management').PagingFiles|Where-Object {$_})
$result=[ordered]@{VerificationRunId=$VerificationRunId;Computer=$env:COMPUTERNAME;UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Success=(-not $system.AutomaticManagedPagefile -and $settings.Count -eq 0 -and $paging.Count -eq 0);RAMGB=[math]::Round($system.TotalPhysicalMemory/1GB,1);AutomaticManagedPagefile=$system.AutomaticManagedPagefile;ConfiguredPagefiles=@($settings.Name);ActivePagefiles=@($usage.Name);ActiveAllocatedMB=($usage|Measure-Object AllocatedBaseSize -Sum).Sum;RequiresRestart=($usage.Count -gt 0);CheckedAt=(Get-Date).ToString('o')}
$result|ConvertTo-Json|Set-Content (Join-Path $root 'Pagefile-Result.json') -Encoding UTF8
$result|Format-List|Out-Host
if(-not $result.Success){throw '分頁檔停用設定驗證失敗。'}
Write-Host '已確認分頁檔設定為停用；不會自動重新開機。' -ForegroundColor Green
