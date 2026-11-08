#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/drivers/driver_plan_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$fixture=Join-Path $env:TEMP ('driver_components_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
foreach($n in @('parent.inf','parent.cat','child.inf','child.cat','package.zip')){[IO.File]::WriteAllText((Join-Path $fixture $n),$n)}
$parent=[pscustomobject]@{Id='mei';InfPath='parent.inf';CatalogPath='parent.cat';InfSHA256=(Get-FileHash (Join-Path $fixture 'parent.inf')).Hash;CatalogSHA256=(Get-FileHash (Join-Path $fixture 'parent.cat')).Hash;DriverVersion='2.0.0.0';Provider='Intel';Architecture='amd64';MinimumBuild=22000;HardwareIds=@('PCI\VEN_8086&DEV_A13A')}
$child=[pscustomobject]@{Id='mei_dal';ParentTarget='mei';PreStage=$true;InfPath='child.inf';CatalogPath='child.cat';InfSHA256=(Get-FileHash (Join-Path $fixture 'child.inf')).Hash;CatalogSHA256=(Get-FileHash (Join-Path $fixture 'child.cat')).Hash;DriverVersion='2.0.0.0';Provider='Intel';Architecture='amd64';MinimumBuild=22000;HardwareIds=@('SWC\3C4852D6-D47B-4F46-B05E-B5EDC1AA440E')}
$entry=[pscustomobject]@{Id='mei';File='package.zip';SHA256=(Get-FileHash (Join-Path $fixture 'package.zip')).Hash;Drivers=@($parent,$child);Files=@()}
$script:events=@();$script:parentPresent=$true;$script:parentVersion='1.0.0.0';$script:childPresent=$false;$script:omitChild=$false;$script:failStage=$false
function Get-SetupDriverDeviceInventory {if($script:parentPresent){[pscustomobject]@{InstanceId='PCI\parent';HardwareIds=$parent.HardwareIds;DriverProvider='Intel';DriverVersion=$script:parentVersion;Status='OK'}};if($script:childPresent){[pscustomobject]@{InstanceId='SWC\child';HardwareIds=$child.HardwareIds;DriverProvider='Intel';DriverVersion='2.0.0.0';Status='OK'}}}
function New-SetupDriverExtractionRoot {$fixture}
function Expand-DriverArchive {param($Archive,$Destination)}
function Assert-SetupDriverPayloadFiles {param($Entry,$Root)}
function Get-AuthenticodeSignature {[pscustomobject]@{Status='Valid';SignerCertificate=[pscustomobject]@{Subject='CN=Microsoft Windows Hardware Compatibility Publisher, O=Microsoft Corporation'}}}
function Invoke-SetupDriverInfInstall {param($InfPath,$LogPath,[switch]$StageOnly) $name=[IO.Path]::GetFileName($InfPath);$script:events+=($name+':'+$StageOnly);if($StageOnly -and $script:failStage){return [pscustomobject]@{ExitCode=5}};if($name -eq 'parent.inf' -and -not $StageOnly){$script:parentVersion='2.0.0.0';if(-not $script:omitChild){$script:childPresent=$true}};[pscustomobject]@{ExitCode=0}}
function Invoke-SetupDriverPnpRescan {$script:events+='scan';[pscustomobject]@{ExitCode=0}}
function Run {Invoke-SetupOfficialDriverPackage -Entry $entry -Archive (Join-Path $fixture 'package.zip') -Build 26100 -LogPath (Join-Path $fixture 'native.log')}
$r=Run
Assert ($script:events[0] -ceq 'child.inf:True' -and $script:events[1] -ceq 'parent.inf:False') ('必要SWC在父裝置安裝前預先進DriverStore；實際='+($script:events -join ','))
Assert ($r.Failures.Count -eq 0 -and @($r.Results|Where-Object Status -in @('Current','Updated')).Count -eq 2) '父與必需子元件均重新枚舉並讀回版本'
$script:events=@();$script:parentVersion='1.0.0.0';$script:childPresent=$false;$script:omitChild=$true;$r=Run
Assert ($r.Failures.Count -gt 0 -and @($r.Results|Where-Object {$_.Status -eq 'Unverified' -and $_.InfPath -eq 'child.inf'}).Count -eq 1) '父裝好但必需子元件未出現不得假稱完整或當Absent略過'
$script:events=@();$script:parentVersion='1.0.0.0';$script:failStage=$true;$r=Run
Assert ($r.Failures.Count -gt 0 -and $script:events.Count -eq 1) '子元件預先加入失敗禁止父裝置部分升級'
$script:events=@();$script:failStage=$false;$script:parentPresent=$false;$r=Run
Assert ($script:events.Count -eq 0 -and @($r.Results|Where-Object Status -eq 'Absent').Count -eq 2) '父硬體未枚舉不預先加入或強裝子元件'
