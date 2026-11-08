#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../../modules/drivers/driver_plan_library.ps1')
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
# Win11 build26200 native /enum-drivers /devices /format xml structure; synthetic device and published INF identity.
$script:xml=@'
<PnpUtil><Driver DriverName="oem_fixture.inf"><OriginalName>amdwddme.inf</OriginalName><ProviderName>Advanced Micro Devices, Inc.</ProviderName><ClassName>Extension</ClassName><ClassGuid>{e2f84ce7-8efa-411c-aa69-97454ca4cb57}</ClassGuid><ExtensionId>{07a2a561-d001-4503-b239-ef2fe0379efb}</ExtensionId><DriverVersion>06/28/2023 31.0.21001.46001</DriverVersion><SignerName>Microsoft Windows Hardware Compatibility Publisher</SignerName><CatalogAttributes>Declarative</CatalogAttributes><WhcpVersion>Unknown</WhcpVersion><Devices><Device InstanceId="PCI\GPU_FIXTURE"><DeviceDescription>Fixture GPU</DeviceDescription><Status>Started</Status></Device></Devices></Driver></PnpUtil>
'@
$native=$script:xml;$script:exit=0
function Get-SetupDriverPnpTool {'Invoke-NativeSchemaFixture'}
function Invoke-NativeSchemaFixture {param([Parameter(ValueFromRemainingArguments=$true)][object[]]$Arguments) $global:LASTEXITCODE=$script:exit;$script:xml}
$target=[pscustomobject]@{InfPath='Display/amdwddme.inf';DriverVersion='31.0.21001.46001';DriverDate='06/28/2023';Provider='Advanced Micro Devices, Inc.';ExtensionId='{07A2A561-D001-4503-B239-EF2FE0379EFB}';MinimumBuild=22000;Architecture='amd64';HardwareIds=@('PCI\VEN_1002&DEV_694C')}
$device=[pscustomobject]@{InstanceId='PCI\GPU_FIXTURE';HardwareIds=$target.HardwareIds;Status='OK';DriverSigned=$true}
$inventory=Get-SetupDriverExtensionInventory
$r=Get-SetupDriverExtensionReadback -Target $target -Devices @($device) -Inventory $inventory -Build 26200
Assert ($inventory.DocumentElement.Name -ceq 'PnpUtil' -and $r.Status -ceq 'Current' -and $r.Association -ceq 'Active') '原生PascalCase schema能讀回精確ExtensionId/版本/供應商/本輪裝置關聯'
foreach($case in @('root','child','missing','duplicate','path','date','namespace','class','extension','version','published','association','duplicateDevices','native','dtd')){
 $script:xml=$native;$script:exit=0
 switch($case){
  root{$script:xml=$native.Replace('PnpUtil','UnknownInventory')}
  child{$script:xml=$native.Replace('<Driver DriverName','<driver DriverName').Replace('</Driver>','</driver>')}
  missing{$script:xml=$native.Replace('<OriginalName>amdwddme.inf</OriginalName>','')}
  duplicate{$script:xml=$native.Replace('<OriginalName>','<OriginalName>other.inf</OriginalName><OriginalName>')}
  path{$script:xml=$native.Replace('amdwddme.inf','../amdwddme.inf')}
  date{$script:xml=$native.Replace('06/28/2023','99/99/2023')}
  namespace{$script:xml=$native.Replace('<PnpUtil>','<PnpUtil xmlns="urn:unknown">')}
  class{$script:xml=$native.Replace('{e2f84ce7-8efa-411c-aa69-97454ca4cb57}','invalid-guid')}
  extension{$script:xml=$native.Replace('{07a2a561-d001-4503-b239-ef2fe0379efb}','invalid-guid')}
  version{$script:xml=$native.Replace('31.0.21001.46001','latest')}
  published{$script:xml=$native.Replace('oem_fixture.inf','../oem_fixture.inf')}
  association{$script:xml=$native.Replace(' InstanceId="PCI\GPU_FIXTURE"','')}
  duplicateDevices{$script:xml=$native.Replace('<Devices>','<Devices/><Devices>')}
  native{$script:exit=87}
  dtd{$script:xml='<!DOCTYPE PnpUtil [<!ENTITY bad SYSTEM "file:///private">]><PnpUtil>&bad;</PnpUtil>'}
 }
 $failed=$false;try{Get-SetupDriverExtensionInventory|Out-Null}catch{$failed=$true}
 Assert $failed ('未知schema/缺重複欄位/非INF basename/無效日期/native錯/DTD保持拒絕 '+$case)
}
$script:exit=0;$script:xml=$native.Replace('PCI\GPU_FIXTURE','PCI\OTHER_FIXTURE');$inventory=Get-SetupDriverExtensionInventory
$r=Get-SetupDriverExtensionReadback -Target $target -Devices @($device) -Inventory $inventory -Build 26200
Assert ($r.Status -ceq 'Staged' -and $r.Association -cne 'Active') '原生schema包存在但未關聯目標GPU仍只能Staged'
