#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../../modules/drivers/driver_plan_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
Assert ([bool](Get-Command Get-SetupDriverExtensionReadback -ErrorAction SilentlyContinue)) '延伸INF依正式XML與裝置關聯驗證，不借用GPU主驅動版本'
$target=[pscustomobject]@{InfPath='Display/amdwddme.inf';DriverVersion='31.0.21001.46001';DriverDate='06/28/2023';Provider='Advanced Micro Devices, Inc.';ExtensionId='{07A2A561-D001-4503-B239-EF2FE0379EFB}';MinimumBuild=22000;Architecture='amd64';HardwareIds=@('PCI\VEN_1002&DEV_694C')}
$device=[pscustomobject]@{InstanceId='PCI\GPU_FIXTURE';HardwareIds=$target.HardwareIds;Status='OK'}
function Xml {param($Version='31.0.21001.46001',$Date='06/28/2023',$Instance='PCI\GPU_FIXTURE',$Provider='Advanced Micro Devices, Inc.',$Id='{07A2A561-D001-4503-B239-EF2FE0379EFB}',$Class='{e2f84ce7-8efa-411c-aa69-97454ca4cb57}',$Original='amdwddme.inf') [xml]('<pnputil><driver DriverName="oem_fixture.inf"><OriginalName>'+ $Original+'</OriginalName><ProviderName>'+$Provider+'</ProviderName><ClassGuid>'+$Class+'</ClassGuid><ExtensionId>'+$Id+'</ExtensionId><DriverVersion>'+$Date+' '+$Version+'</DriverVersion><Devices count="1"><Device InstanceId="'+$Instance+'"/></Devices></driver></pnputil>')}
function Read {param($Xml=(Xml),$Devices=@($device)) Get-SetupDriverExtensionReadback -Target $target -Devices $Devices -Inventory $Xml -Build 26100}
$r=Read;Assert ($r.Status -eq 'Current' -and $r.Association -eq 'Active' -and $r.CurrentVersion -eq $target.DriverVersion) '同ExtensionId/INF/provider/version且精確關聯正常GPU才算Active'
$r=Read -Xml (Xml -Instance 'PCI\another_device');Assert ($r.Status -eq 'Staged' -and $r.Association -ne 'Active') '包在DriverStore但未關聯本輪裝置只可Staged'
$r=Read -Xml (Xml -Version '30.0.0.1');Assert ($r.Status -eq 'UpdateRequired') '已關聯的較舊Extension不可冒充GPU主版達標'
$r=Read -Xml (Xml -Version '32.0.0.1');Assert ($r.Status -eq 'NewerInstalled') '同lineage較新已關聯Extension保留，不降版'
foreach($bad in @((Xml -Provider 'Unknown Vendor'),(Xml -Id '{00000000-0000-0000-0000-000000000000}'),(Xml -Class '{00000000-0000-0000-0000-000000000000}'),(Xml -Original 'other.inf'))){Assert ((Read -Xml $bad).Status -eq 'Unverified') '不符provider/lineage/class/原INF的候選不可信'}
$device.Status='Error';Assert ((Read).Status -eq 'Unverified') 'Extension包正確但所綁裝置異常不通過';$device.Status='OK'
Assert ((Read -Devices @()).Status -eq 'Absent') '未枚舉Extension硬體不猜測或創造裝置'
function Get-SetupDriverPnpTool {'Invoke-InertDriverXml'}
$script:xml=(Xml).OuterXml;$script:code=0
function Invoke-InertDriverXml {param([Parameter(ValueFromRemainingArguments=$true)][object[]]$NativeArgs) $script:nativeArgs=$NativeArgs;$global:LASTEXITCODE=$script:code;return $script:xml}
$xml=Get-SetupDriverExtensionInventory
Assert ($xml.DocumentElement.LocalName -eq 'pnputil' -and ($script:nativeArgs -join '|') -ceq '/enum-drivers|/devices|/format|xml') '正式只讀native adapter要求XML及裝置關聯，不解析本地化文字'
foreach($case in @('native','invalid','dtd')){$script:code=0;$script:xml=(Xml).OuterXml;switch($case){native{$script:code=87} invalid{$script:xml='not xml'} dtd{$script:xml='<!DOCTYPE pnputil [<!ENTITY external SYSTEM "file:///private">]><pnputil>&external;</pnputil>'}};$failed=$false;try{Get-SetupDriverExtensionInventory|Out-Null}catch{$failed=$true};Assert $failed ('native錯誤/無XML能力/不可信DTD不可假驗證：'+$case)}
