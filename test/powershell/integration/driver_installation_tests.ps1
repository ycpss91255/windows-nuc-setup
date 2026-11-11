#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$library=Join-Path $root 'modules/drivers/driver_installation_library.ps1'
Assert (Test-Path -LiteralPath $library) '版本2驅動完整入口提供可安全測試的正式編排來源'
. (Join-Path $root 'core/hardware.ps1');. $library
$fixture=Join-Path $env:TEMP ('driver_installation_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
$zip=Join-Path $fixture 'wifi.zip';[IO.File]::WriteAllText($zip,'inert archive')
$entry=@{Id='wifi';File='wifi.zip';SHA256=(Get-FileHash $zip).Hash;SourceUrl='https://www.intel.com/driver';PackageVersion='22.200.2';Files=@(@{Path='wifi.inf';SHA256=('A'*64)});Drivers=@(@{InfPath='wifi.inf';CatalogPath='wifi.cat';InfSHA256=('A'*64);CatalogSHA256=('B'*64);DriverVersion='20.70.32.1';Provider='Intel';Architecture='amd64';MinimumBuild=22000;HardwareIds=@('PCI\VEN_8086&DEV_24FD')})}
@{SchemaVersion=2;Packages=@($entry)}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $fixture 'manifest.json') -Encoding UTF8
$script:calls=0;$script:fail=$false;$script:problems=@()
function Get-CimInstance {param($ClassName,$ErrorAction) if($ClassName -eq 'Win32_OperatingSystem'){[pscustomobject]@{BuildNumber='26100'}}elseif($ClassName -eq 'Win32_VideoController'){[pscustomobject]@{Name='fixture';DriverVersion='1.2.3.4';ConfigManagerErrorCode=0}}}
function Get-PnpDevice {param([switch]$PresentOnly,$ErrorAction) $script:problems}
function Invoke-SetupOfficialDriverPackage {param($Entry,$Archive,$Build,$LogPath) $script:calls++;$script:last=@($Entry.Id,$Archive,$Build);[pscustomobject]@{Results=@([pscustomobject]@{Status='Updated';InfPath='wifi.inf'});Failures=@(if($script:fail){'fixture failure'});RebootRequired=$true}}
$out=Join-Path $fixture 'logs'
$result=Invoke-SetupDriverInstallation -DriverRoot $fixture -LogDirectory $out
Assert ($result.Success -and $script:calls -eq 1 -and $script:last[0] -ceq 'wifi' -and $script:last[1] -ceq $zip -and $script:last[2] -eq 26100) '真正完整編排讀v2清單與實際OS並傳給正式套件安裝邊界'
Assert ($result.Targets[0].Status -ceq 'Updated' -and $result.RebootRequired) '逐裝置讀回與3010需要重開狀態保留'
$saved=Get-Content -LiteralPath (Join-Path $out 'driver_result.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert ($saved.Success -and $saved.Targets.Count -eq 1) '完整正式結果落盤而非只看PnP無驚嘆號'
$script:fail=$true;$result=Invoke-SetupDriverInstallation -DriverRoot $fixture -LogDirectory $out
Assert (-not $result.Success -and $result.Failures[0] -eq 'fixture failure') '原生失敗結果與最終Success一致'
$script:fail=$false;$script:problems=@([pscustomobject]@{Status='Error';Class='USB';InstanceId='USB\fixture';FriendlyName='problem'})
$result=Invoke-SetupDriverInstallation -DriverRoot $fixture -LogDirectory $out
Assert (-not $result.Success -and $result.ProblemCount -eq 1) '既有裝置異常不被版本檢查掩蓋'
$script:calls=0;[IO.File]::AppendAllText($zip,'tampered');$rejected=$false
try{Invoke-SetupDriverInstallation -DriverRoot $fixture -LogDirectory $out}catch{$rejected=$_.Exception.Message -match 'SHA256'}
Assert ($rejected -and $script:calls -eq 0) '封存檔損壞在任何安裝前拒絕'
