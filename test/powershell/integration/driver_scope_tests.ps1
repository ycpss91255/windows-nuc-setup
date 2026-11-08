#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../../core/hardware.ps1')
. (Join-Path $PSScriptRoot '../../../modules/drivers/driver_installation_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$fixture=Join-Path $env:TEMP ('driver_scope_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture);[IO.File]::WriteAllText((Join-Path $fixture 'package.zip'),'inert')
$gpu=[pscustomobject]@{Id='gpu';InfPath='gpu.inf';HardwareIds=@('PCI\VEN_8086&DEV_5912');Provider='Intel';DriverVersion='31.0.101.2145';MinimumBuild=22000;Architecture='amd64'}
$audio=[pscustomobject]@{Id='audio';InfPath='audio.inf';HardwareIds=@('PCI\VEN_8086&DEV_A171');Provider='Intel';DriverVersion='1.0.0.0';MinimumBuild=22000;Architecture='amd64'}
$entry=[pscustomobject]@{Id='intel_graphics';ScopeTarget='gpu';File='package.zip';SHA256=(Get-FileHash (Join-Path $fixture 'package.zip')).Hash;Drivers=@($gpu,$audio);Files=@()}
function Get-SetupDriverDeviceInventory {param($Targets) [pscustomobject]@{InstanceId='PCI\audio';HardwareIds=$audio.HardwareIds;DriverProvider='Microsoft';DriverVersion='10.0.0.1';Status='OK'}}
$script:staged=0
function New-SetupDriverExtractionRoot {$script:staged++;$fixture}
function Expand-DriverArchive {}
function Assert-SetupDriverPayloadFiles {}
function Assert-SetupDriverTargetIntegrity {$true}
function Invoke-SetupDriverTarget {param($Target) [pscustomobject]@{Results=@([pscustomobject]@{Status='Updated';InfPath=$Target.InfPath});Failures=@();RebootRequired=$false}}
$result=Invoke-SetupOfficialDriverPackage -Entry $entry -Archive (Join-Path $fixture 'package.zip') -Build 26100 -LogPath 'inert.log'
Assert ($script:staged -eq 0 -and $result.Failures.Count -eq 0 -and @($result.Results|Where-Object Status -eq 'NotApplicable').Count -eq 2) 'GPU未枚舉時整個受限圖形包不解壓不裝共享音效控制器'
$entry|Add-Member PackageVersion '31.0.101.2145';$entry|Add-Member SourceUrl 'https://www.intel.com/driver'
@{SchemaVersion=2;AuditedAt='2026-11-08';Packages=@($entry)}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $fixture 'manifest.json') -Encoding UTF8
function Get-CimInstance {param($ClassName,$ErrorAction) [pscustomobject]@{BuildNumber='26100'}}
$result=Invoke-SetupDriverVerification -DriverRoot $fixture
Assert (@($result.Targets|Where-Object Status -eq 'NotApplicable').Count -eq 2 -and $script:staged -eq 0) '最後唯讀核實保留相同父硬體作用範圍'
