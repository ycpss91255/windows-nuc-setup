#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/drivers/driver_plan_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
function Get-CimInstance {param($ClassName,$ErrorAction) [pscustomobject]@{DeviceID='USB\VID_8087&PID_0A2B\target';DriverProviderName='Intel';DriverVersion='22.200.0.2'}}
function Get-PnpDevice {param([switch]$PresentOnly,$ErrorAction) @([pscustomobject]@{InstanceId='SWD\unrelated\virtual';FriendlyName='virtual';Status='OK'},[pscustomobject]@{InstanceId='USB\VID_8087&PID_0A2B\target';FriendlyName='BT';Status='OK'})}
$script:targetFailure=$false
function Get-PnpDeviceProperty {param($InstanceId,$KeyName,$ErrorAction) if($InstanceId -like 'SWD*' -or $script:targetFailure){throw 'property read failure'};[pscustomobject]@{Data=@('USB\VID_8087&PID_0A2B')}}
$errorText='';$inventory=@();try{$inventory=@(Get-SetupDriverDeviceInventory)}catch{$errorText=$_.Exception.Message}
Assert (-not $errorText -and $inventory.Count -eq 2) ('無關虛擬裝置缺硬體屬性不終止整輪：'+$errorText)
$t=[pscustomobject]@{InfPath='ibtusb.inf';HardwareIds=@('USB\VID_8087&PID_0A2B');Provider='Intel';DriverVersion='22.200.0.2';MinimumBuild=22000;Architecture='amd64'}
Assert ((Get-SetupDriverTargetPlan -Target $t -Devices $inventory -Build 26100 -Architecture amd64).Status -eq 'Current') '無關屬性錯誤不掩蓋可讀目標'
$script:targetFailure=$true;$inventory=@(Get-SetupDriverDeviceInventory)
Assert ($inventory[1].HardwareIdsReadError -eq 'property read failure') '目標屬性讀取失敗保存錯誤證據'
$plan=Get-SetupDriverTargetPlan -Target $t -Devices $inventory -Build 26100 -Architecture amd64
Assert ($plan.Status -eq 'Unverified') '目標屬性失敗不得靜默列Absent或Current'
$t.HardwareIds=@('USB\VID_8087&PID_0A2B0')
Assert ((Get-SetupDriverTargetPlan -Target $t -Devices $inventory -Build 26100 -Architecture amd64).Status -eq 'Absent') '失敗InstanceId仍不得substring匹配另一PID'
