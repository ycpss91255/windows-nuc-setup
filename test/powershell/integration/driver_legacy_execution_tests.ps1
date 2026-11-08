#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'core/hardware.ps1');. (Join-Path $root 'modules/drivers/driver_installation_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$fixture=Join-Path $env:TEMP ('driver_legacy_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
Add-Type -AssemblyName System.IO.Compression.FileSystem
$names=@('Chipset.zip','SerialIO.zip','UCM.zip','GFX-Radeon.zip')
foreach($name in $names){
 $source=Join-Path $fixture ($name+'.source');[void][IO.Directory]::CreateDirectory((Join-Path $source 'Windows10-x64'))
 $files=switch($name){'Chipset.zip'{@('Windows10-x64/system.inf')} 'SerialIO.zip'{@('serial.inf')} 'UCM.zip'{@('TPS659xx.inf')} 'GFX-Radeon.zip'{@('u0393589.inf','AtihdWT6.inf')}}
 foreach($file in $files){[IO.File]::WriteAllText((Join-Path $source $file),'PCI\VEN_8086&DEV_A123')}
 [IO.Compression.ZipFile]::CreateFromDirectory($source,(Join-Path $fixture $name))
}
$manifest=@($names|ForEach-Object {@{File=$_;SHA256=(Get-FileHash (Join-Path $fixture $_)).Hash}})
$manifest|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $fixture 'manifest.json') -Encoding UTF8
@{SchemaVersion=1;HardwareProfile='NUC8';Architecture='x64';SupportedBoards=@('NUC8i7HVB','NUC8i7HNB')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $fixture 'package.json') -Encoding UTF8
$script:installs=@();$script:code=0;$script:amd=$true;$script:ids=@('PCI\VEN_8086&DEV_A123')
function New-SetupDriverExtractionRoot {$p=Join-Path $fixture ('private_fixture_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($p);$p}
function Get-PnpDevice {param($Class,[switch]$PresentOnly,$ErrorAction) if($Class -eq 'Display'){if($script:amd){[pscustomobject]@{InstanceId='PCI\VEN_1002&DEV_694C\fixture';Status='OK'}}}else{[pscustomobject]@{InstanceId='PCI\fixture';Status='OK'}}}
function Get-PnpDeviceProperty {param([Parameter(ValueFromPipeline=$true)]$InputObject,$KeyName) process{[pscustomobject]@{Data=$script:ids}}}
function Get-CimInstance {param($ClassName,$ErrorAction) if($ClassName -eq 'Win32_VideoController'){[pscustomobject]@{Name='fixture';DriverVersion='1.2.3.4';ConfigManagerErrorCode=0}}}
function Invoke-SetupDriverInfInstall {param($InfPath,$LogPath) $script:installs+=[IO.Path]::GetFileName($InfPath);[pscustomobject]@{ExitCode=$script:code}}
$result=Invoke-SetupDriverInstallation -DriverRoot $fixture -LogDirectory (Join-Path $fixture 'logs')
Assert ($result.Success -and $script:installs.Count -eq 5 -and 'TPS659xx.inf' -in $script:installs -and 'AtihdWT6.inf' -in $script:installs) '四包舊格式經真正公開編排仍精確選五個INF，無原生安裝'
$script:installs=@();$script:code=3010;$result=Invoke-SetupLegacyDriverPackages -Entries $manifest -DriverRoot $fixture -LogDirectory (Join-Path $fixture 'logs') -Stamp 'reboot'
Assert ($result.RebootRequired -and $result.Failures.Count -eq 0 -and $script:installs.Count -eq 5) '舊包正常原生3010保留而不自行重開'
$script:code=5;$result=Invoke-SetupLegacyDriverPackages -Entries $manifest -DriverRoot $fixture -LogDirectory (Join-Path $fixture 'logs') -Stamp 'failure'
Assert ($result.Failures.Count -eq 5) '舊包每個原生失敗都保留，不能只看無異常裝置'
$script:code=0;$script:amd=$false;$script:installs=@();$result=Invoke-SetupLegacyDriverPackages -Entries $manifest -DriverRoot $fixture -LogDirectory (Join-Path $fixture 'logs') -Stamp 'no_gpu'
Assert ($script:installs.Count -eq 3 -and 'u0393589.inf' -notin $script:installs) '沒有相符Radeon裝置即略過AMD包'
$script:amd=$true;$script:ids=@('PCI\VEN_9999&DEV_0000');$script:installs=@();$result=Invoke-SetupLegacyDriverPackages -Entries $manifest -DriverRoot $fixture -LogDirectory (Join-Path $fixture 'logs') -Stamp 'unmatched'
Assert ($script:installs.Count -eq 0) 'INF無相符硬體不加入其他平台驅動'
$packageResult=@(. (Join-Path $root 'modules/drivers/install_drivers.ps1') -PackageOnly -DriverPackagePath $fixture)
Assert ($packageResult.Count -eq 1 -and $packageResult[0].Status -eq 'Passed' -and $packageResult[0].Count -eq 4) '真正交付entry保留舊四包離線驗包，沒有原生裝置操作'
$rejected=$false;try{. (Join-Path $root 'modules/drivers/install_drivers.ps1') -PackageOnly -VerifyOnly}catch{$rejected=$_.Exception.Message -match '不可混用'}
Assert $rejected '公開entry拒絕把離線驗包與系統驗證混用'
