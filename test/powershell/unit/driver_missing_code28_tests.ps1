#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/drivers/driver_plan_library.ps1')
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$manifest=Get-Content -LiteralPath (Join-Path $root 'drivers/nuc8i7hvk_hnk/manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
$script:ids=@('PCI\VEN_8086&DEV_1911','PCI\VEN_8086&DEV_A127','PCI\VEN_8086&DEV_A131','ACPI\INT3515')
$targets=@($manifest.Packages|ForEach-Object Drivers|Where-Object {@($_.HardwareIds|Where-Object {$_ -in $script:ids}).Count})
Assert ($targets.Count -eq 5) '既有官方manifest已涵蓋四個裝置與A127兩個目標，無須缺包假設'
$script:deviceStatus='Error';$script:problem=28;$script:installedInf=$null;$script:provider=$null;$script:version=$null;$script:signed=$null;$script:signer=$null;$script:readFailure='';$script:missingProperty='';$script:noCim=$false
function Get-PnpDevice {param([switch]$PresentOnly,$ErrorAction) if(-not $PresentOnly){throw 'must query present devices'};foreach($id in $script:ids){[pscustomobject]@{InstanceId=($id+'\fixture');Status=$script:deviceStatus;FriendlyName='Code28 fixture';Class='System'}}}
function Get-CimInstance {param($ClassName,$ErrorAction) if($ClassName -ne 'Win32_PnPSignedDriver'){throw 'unexpected class'};if(-not $script:noCim){foreach($id in $script:ids){[pscustomobject]@{DeviceID=($id+'\fixture');DriverProviderName=$script:provider;DriverVersion=$script:version;InfName=$script:installedInf;IsSigned=$script:signed;Signer=$script:signer}}}}
function Get-PnpDeviceProperty {
 param($InstanceId,$KeyName,$ErrorAction)
 if($KeyName -eq $script:missingProperty){return $null}
 if($KeyName -eq $script:readFailure){throw 'fixture metadata read failed'}
 $data=switch($KeyName){
  'DEVPKEY_Device_HardwareIds' {@($InstanceId.Substring(0,$InstanceId.LastIndexOf('\')))}
  'DEVPKEY_Device_CompatibleIds' {@()}
  'DEVPKEY_Device_ProblemCode' {$script:problem}
  'DEVPKEY_Device_DriverInfPath' {$script:installedInf}
  default{throw ('unexpected native property '+$KeyName)}
 }
 [pscustomobject]@{Data=$data}
}
function Plans {$devices=@(Get-SetupDriverDeviceInventory -Targets $targets);foreach($t in $targets){Get-SetupDriverTargetPlan -Target $t -Devices $devices -Build 26200 -Architecture amd64}}
$plans=@(Plans)
Assert ($plans.Count -eq 5 -and @($plans|Where-Object Status -ne 'UpdateRequired').Count -eq 0) '真實Code28且INF版本供應商簽章全空必須進入已核相符驅動安裝計畫'
foreach($case in @('code_zero','malformed_code','installed_inf','signer_only','signed_metadata','native_read_failure','inf_read_failure','missing_property','hardware_read_failure')){
 $script:deviceStatus='Error';$script:problem=28;$script:installedInf=$null;$script:provider=$null;$script:version=$null;$script:signed=$null;$script:signer=$null;$script:readFailure=''
 switch($case){code_zero{$script:problem=0} malformed_code{$script:problem='28'} installed_inf{$script:installedInf='oem42.inf'} signer_only{$script:signer='CN=Contradictory signer'} signed_metadata{$script:provider='Unknown Vendor';$script:version='1.0';$script:signed=$false} native_read_failure{$script:readFailure='DEVPKEY_Device_ProblemCode'} inf_read_failure{$script:readFailure='DEVPKEY_Device_DriverInfPath'} missing_property{$script:missingProperty='DEVPKEY_Device_DriverInfPath'} hardware_read_failure{$script:readFailure='DEVPKEY_Device_HardwareIds'}}
 Assert (@(@(Plans)|Where-Object Status -eq 'UpdateRequired').Count -eq 0) ('矛盾或讀取失敗仍然拒絕安裝 '+$case)
}
$script:problem=28;$script:readFailure='';$script:missingProperty='';$script:provider=$null;$script:version=$null;$script:signed=$null;$script:signer=$null;$script:noCim=$true
Assert (@(@(Plans)|Where-Object Status -eq 'UpdateRequired').Count -eq 5) '原生確認缺驅動時CIM完全無記錄也可計畫安裝'
$script:noCim=$false;$devices=@(Get-SetupDriverDeviceInventory -Targets $targets)
$r=Get-SetupDriverReadback -Plan $plans[0] -Devices $devices
Assert ($r.Status -eq 'Unverified') '安裝後仍是Code28且無驅動不能回報Updated'
$script:provider='Intel Corporation';$script:version='99.0.0.0';$script:signed=$false;$script:installedInf='oem42.inf'
Assert (@(@(Plans)|Where-Object Status -eq 'UpdateRequired').Count -eq 0) '真已安裝unsigned不因Code28而降低簽章門檻'
# Exercise the original installer controller too; native install/signature boundaries are isolated.
$script:deviceStatus='Error';$script:provider=$null;$script:version=$null;$script:signed=$null;$script:signer=$null;$script:installedInf=$null;$script:readFailure='';$script:missingProperty='';$script:problem=28
$temp=Join-Path ([IO.Path]::GetTempPath()) ('missing_driver_install_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
[IO.File]::WriteAllText((Join-Path $temp 'driver.inf'),'synthetic pinned INF');[IO.File]::WriteAllText((Join-Path $temp 'driver.cat'),'synthetic pinned CAT')
$script:target=$targets[0].PSObject.Copy();$script:target.InfPath='driver.inf';$script:target.CatalogPath='driver.cat';$script:target.InfSHA256=(Get-FileHash (Join-Path $temp 'driver.inf')).Hash;$script:target.CatalogSHA256=(Get-FileHash (Join-Path $temp 'driver.cat')).Hash
function Get-AuthenticodeSignature {param($LiteralPath,$ErrorAction) [pscustomobject]@{Status='Valid';SignerCertificate=[pscustomobject]@{Subject='CN=Microsoft Windows Hardware Compatibility Publisher, O=Fixture'}}}
$script:installCalls=0;$script:completeNative=$true
function Invoke-SetupDriverInfInstall {param($InfPath,$LogPath) if($InfPath -cne (Join-Path $temp 'driver.inf')){throw 'unapproved native INF'};$script:installCalls++;if($script:completeNative){$script:deviceStatus='OK';$script:provider=$script:target.Provider;$script:version=$script:target.DriverVersion;$script:signed=$true;$script:installedInf='oem42.inf';$script:problem=0};[pscustomobject]@{ExitCode=0}}
$r=Invoke-SetupDriverTarget -Target $script:target -Root $temp -Build 26200 -Architecture amd64 -LogPath (Join-Path $temp 'native.log')
Assert ($script:installCalls -eq 1 -and $r.Failures.Count -eq 0 -and $r.Results[0].Status -eq 'Updated') '真controller在無驅動時驗hash及CAT後呼叫安裝並以正常簽章版本讀回Updated'
$script:completeNative=$false;$script:deviceStatus='Error';$script:provider=$null;$script:version=$null;$script:signed=$null;$script:signer=$null;$script:installedInf=$null;$script:problem=28
$r=Invoke-SetupDriverTarget -Target $script:target -Root $temp -Build 26200 -Architecture amd64 -LogPath (Join-Path $temp 'native.log')
Assert ($script:installCalls -eq 2 -and $r.Failures.Count -gt 0 -and $r.Results[0].Status -eq 'Unverified') 'native退出0但實際仍缺驅動時真controller保留failure'