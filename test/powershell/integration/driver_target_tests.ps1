#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/drivers/driver_plan_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
Assert ([bool](Get-Command Invoke-SetupDriverTarget -ErrorAction SilentlyContinue)) '版本2具名編排先驗再裝並讀回'
$t=[pscustomobject]@{InfPath='net.inf';HardwareIds=@('USB\VID_8087&PID_0A2B&REV_0010');Provider='Intel Corporation';DriverVersion='22.200.0.2';MinimumBuild=22000;Architecture='amd64'}
$script:device=[pscustomobject]@{InstanceId='USB\fixture';HardwareIds=@('USB\VID_8087&PID_0A2B&REV_0010');DriverProvider='Intel Corporation';DriverVersion='21.90.0.4';Status='OK'}
$script:calls=0;$script:integrity=0;$script:change=$true;$script:exit=0
function Get-SetupDriverDeviceInventory { $script:device }
function Assert-SetupDriverTargetIntegrity {$script:integrity++;return $true}
function Invoke-SetupDriverInfInstall {param($InfPath,$LogPath) $script:calls++;if($script:change){$script:device.DriverVersion='22.200.0.2'};[pscustomobject]@{ExitCode=$script:exit}}
function Run {Invoke-SetupDriverTarget -Target $t -Root $env:TEMP -Build 22621 -Architecture amd64 -LogPath 'fixture.log'}
$r=Run;Assert ($r.Results[0].Status -eq 'Updated' -and $script:calls -eq 1 -and $script:integrity -eq 1) '真編排只安裝一次並核實版本更新'
$script:calls=0;$script:device.DriverVersion='23.0.0.1';$r=Run;Assert ($r.Results[0].Status -eq 'NewerInstalled' -and $script:calls -eq 0) '較新已裝完全不呼叫PnP'
$script:device.HardwareIds=@('USB\VID_8087&PID_0A2B&REV_0001');$r=Run;Assert ($r.Results[0].Status -eq 'Absent' -and $script:calls -eq 0) '同PID不同REV非目標不安裝'
$script:device.HardwareIds=$t.HardwareIds;$script:device.DriverVersion='21.90.0.4';$script:change=$false;$r=Run;Assert ($r.Results[0].Status -eq 'Unverified' -and $r.Failures.Count -eq 1) 'native exit0版本不變仍報未核實失敗'
$script:exit=3010;$r=Run;Assert ($r.RebootRequired -and $r.Results[0].Status -eq 'Unverified') '需重開保持未核實而不重啟或假通過'
$script:exit=5;$r=Run;Assert ($r.Failures.Count -ge 1) 'native失敗保留失敗'
$script:calls=0;function Assert-SetupDriverTargetIntegrity {throw 'tampered'};$failed=$false;try{Run}catch{$failed=$true};Assert ($failed -and $script:calls -eq 0) '完整性失敗必須零安裝'