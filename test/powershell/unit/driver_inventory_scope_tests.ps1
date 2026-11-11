#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../../modules/drivers/driver_plan_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$script:reads=@()
function Get-CimInstance {param($ClassName,$ErrorAction)}
function Get-PnpDevice {param([switch]$PresentOnly,$ErrorAction) @([pscustomobject]@{InstanceId='USB\VID_8087&PID_0A2B\target';Class='Bluetooth';Status='OK'},[pscustomobject]@{InstanceId='USB\VID_9999&PID_0001\unrelated';Class='USB';Status='OK'},[pscustomobject]@{InstanceId='SWD\DRIVERENUM\fixture';Class='SoftwareComponent';Status='OK'})}
function Get-PnpDeviceProperty {param($InstanceId,$KeyName,$ErrorAction) $script:reads+=$InstanceId;[pscustomobject]@{Data=@($(if($InstanceId -like 'SWD*'){'SWC\GUID-FIXTURE'}else{'USB\VID_8087&PID_0A2B&REV_0010'}))}}
$targets=@([pscustomobject]@{HardwareIds=@('USB\VID_8087&PID_0A2B&REV_0010')},[pscustomobject]@{HardwareIds=@('SWC\GUID-FIXTURE')})
$inventory=@(Get-SetupDriverDeviceInventory -Targets $targets)
Assert ($inventory.Count -eq 2 -and $script:reads.Count -eq 4 -and -not @($script:reads|Where-Object {$_ -like '*9999*'}).Count) '只查已宣告候選硬體，避免每INF重查整機數百項屬性'
Assert (@($inventory.HardwareIds|Where-Object {$_ -eq 'SWC\GUID-FIXTURE'}).Count -eq 1) 'SWD實例名稱的SoftwareComponent仍由精確SWC硬體屬性匹配'
Assert (@($inventory.HardwareIds|Where-Object {$_ -eq 'USB\VID_8087&PID_0A2B&REV_0010'}).Count -eq 1) 'USB實例省略REV仍查屬性，不能漏掉有REV的官方INF'
function Get-PnpDeviceProperty {param($InstanceId,$KeyName,$ErrorAction) if($InstanceId -like 'SWD*'){throw 'unreadable software component'};[pscustomobject]@{Data=@('USB\VID_8087&PID_0A2B&REV_0010')}}
$inventory=@(Get-SetupDriverDeviceInventory -Targets $targets)
$target=[pscustomobject]@{HardwareIds=@('SWC\GUID-FIXTURE');MinimumBuild=22000;Architecture='amd64';DriverVersion='2.0.0.0';Provider='Intel';InfPath='child.inf'}
Assert ((Get-SetupDriverTargetPlan -Target $target -Devices $inventory -Build 26100 -Architecture amd64).Status -eq 'Unverified') 'SWD實例無法讀SWC識別時不得當成必需子元件不存在'
