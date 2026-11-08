#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../../modules/drivers/driver_installation_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
Assert ([bool](Get-Command Invoke-SetupDriverExtensionTarget -ErrorAction SilentlyContinue)) '完整安裝可補齊Extension且依真Active關聯讀回'
$fixture=Join-Path $env:TEMP ('extension_install_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
foreach($n in @('extension.inf','extension.cat')){[IO.File]::WriteAllText((Join-Path $fixture $n),$n)}
$target=[pscustomobject]@{Id='extension';InfPath='extension.inf';CatalogPath='extension.cat';InfSHA256=(Get-FileHash (Join-Path $fixture 'extension.inf')).Hash;CatalogSHA256=(Get-FileHash (Join-Path $fixture 'extension.cat')).Hash;DriverDate='06/28/2023';DriverVersion='31.0.21001.46001';Provider='AMD';ExtensionId='{07A2A561-D001-4503-B239-EF2FE0379EFB}';Architecture='amd64';MinimumBuild=22000;HardwareIds=@('PCI\VEN_1002&DEV_694C')}
$script:bound=$false;$script:calls=0;$script:fail=$false;$script:newer=$false;$script:present=$true
function Get-SetupDriverDeviceInventory {param($Targets) if($script:present){[pscustomobject]@{InstanceId='PCI\fixture';HardwareIds=$target.HardwareIds;Status='OK'}}}
function Get-AuthenticodeSignature {[pscustomobject]@{Status='Valid';SignerCertificate=[pscustomobject]@{Subject='CN=Microsoft Windows Hardware Compatibility Publisher, O=Microsoft Corporation'}}}
function Get-SetupDriverExtensionInventory {$id=if($script:bound){'PCI\fixture'}else{'PCI\other'};$v=if($script:newer){'32.0.0.1'}else{'31.0.21001.46001'};[xml]('<pnputil><driver DriverName="oem_fixture.inf"><OriginalName>extension.inf</OriginalName><ProviderName>AMD</ProviderName><ClassGuid>{e2f84ce7-8efa-411c-aa69-97454ca4cb57}</ClassGuid><ExtensionId>{07A2A561-D001-4503-B239-EF2FE0379EFB}</ExtensionId><DriverVersion>06/28/2023 '+$v+'</DriverVersion><Devices count="1"><Device InstanceId="'+$id+'"/></Devices></driver></pnputil>')}
function Invoke-SetupDriverInfInstall {param($InfPath,$LogPath) $script:calls++;if(-not $script:fail){$script:bound=$true};[pscustomobject]@{ExitCode=$(if($script:fail){5}else{0})}}
function Run {Invoke-SetupDriverExtensionTarget -Target $target -Root $fixture -Build 26100 -LogPath (Join-Path $fixture 'native.log')}
$r=Run;Assert ($script:calls -eq 1 -and $r.Results[0].Status -eq 'Updated' -and $r.Results[0].Association -eq 'Active' -and $r.Failures.Count -eq 0) '只在原生安裝後同Extension已關聯才報Updated'
$script:calls=0;$script:newer=$true;$r=Run;Assert ($script:calls -eq 0 -and $r.Results[0].Status -eq 'NewerInstalled') '較新已Active延伸包不呼叫安裝或刪除'
$script:newer=$false;$script:bound=$false;$script:fail=$true;$r=Run;Assert ($r.Failures.Count -gt 0 -and $r.Results[0].Status -ne 'Updated') 'native失敗或仍Staged不得報安裝成功'
$script:present=$false;$script:calls=0;$r=Run;Assert ($script:calls -eq 0 -and $r.Results[0].Status -eq 'Absent') 'Extension沒有實際對象時不強裝'
