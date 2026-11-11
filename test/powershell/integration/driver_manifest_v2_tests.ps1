#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'core/hardware.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('driver_manifest_v2_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
@{SchemaVersion=1;HardwareProfile='NUC8';Architecture='x64';SupportedBoards=@('NUC8i7HVB','NUC8i7HNB')}|ConvertTo-Json|Set-Content (Join-Path $fixture 'package.json') -Encoding UTF8
$entries=@(1..5|ForEach-Object {
 $name='fixture_'+$_+'.zip';[IO.File]::WriteAllText((Join-Path $fixture $name),'fixture, never installed')
 [ordered]@{Id=('driver_'+$_);File=$name;SHA256=(Get-FileHash (Join-Path $fixture $name)).Hash;SourceUrl='https://www.intel.com/content/www/us/en/download/774186/driver.html';PackageVersion='22.200.0';HardwareIds=@('USB\VID_8087&PID_0A2B');InfPaths=@('driver/ibtusb.inf');Provider='Intel Corporation';DriverVersion='22.200.0.2';MinimumBuild=22000;Architecture='amd64'}
})
foreach($entry in $entries){
 $entry.Drivers=@([ordered]@{InfPath=$entry.InfPaths[0];HardwareIds=$entry.HardwareIds;Provider=$entry.Provider;DriverVersion=$entry.DriverVersion;MinimumBuild=$entry.MinimumBuild;Architecture=$entry.Architecture})
 foreach($key in @('InfPaths','HardwareIds','Provider','DriverVersion','MinimumBuild','Architecture')){$entry.Remove($key)}
}
$entries[0].Drivers+=@([ordered]@{InfPath='driver/other.inf';HardwareIds=@('ACPI\INT3515');Provider='Texas Instruments';DriverVersion='1.0.10.3';MinimumBuild=22000;Architecture='amd64'})
$manifest=[ordered]@{SchemaVersion=2;Packages=$entries}
function SaveManifest {$manifest|ConvertTo-Json -Depth 8|Set-Content (Join-Path $fixture 'manifest.json') -Encoding UTF8}
SaveManifest
$h=Get-SetupHardwareProfile -BoardProduct NUC8i7HVB
$answer=$null;$errorText='';try{$answer=Test-SetupDriverPayload -Hardware $h -DriverPackagePath $fixture}catch{$errorText=$_.Exception.Message}
Assert ($answer.Count -eq 5 -and $answer.Status -eq 'Passed') ('版本2接受五個具來源與USB硬體識別的封存檔；實際：'+$errorText)
foreach($case in @('Duplicate','Traversal','UntrustedSource','MissingVersion','WrongArchitecture','InvalidHardware','NoInf','InvalidBuild')){
 $saved=$manifest|ConvertTo-Json -Depth 8
 switch($case){
 Duplicate{$manifest.Packages[4].Id=$manifest.Packages[0].Id}
 Traversal{$manifest.Packages[0].Drivers[0].InfPath='../outside.inf'}
 UntrustedSource{$manifest.Packages[0].SourceUrl='https://intel.com.attacker.invalid/driver'}
 MissingVersion{$manifest.Packages[0].Drivers[0].DriverVersion=''}
 WrongArchitecture{$manifest.Packages[0].Drivers[0].Architecture='x86'}
 InvalidHardware{$manifest.Packages[0].Drivers[0].HardwareIds=@('USB\VID_8087*')}
 NoInf{$manifest.Packages[0].Drivers=@()}
 InvalidBuild{$manifest.Packages[0].Drivers[0].MinimumBuild=0}
 }
 SaveManifest;$failed=$false;try{Test-SetupDriverPayload $h $fixture|Out-Null}catch{$failed=$true}
 Assert $failed ('版本2拒絕不可信規格：'+$case)
 $manifest=$saved|ConvertFrom-Json
}
SaveManifest
$export=Join-Path $fixture 'exported'
$exportError='';$exportResult=$null
try{$exportResult=& (Join-Path $root 'script/package/export_driver_package.ps1') -SourceDirectory $fixture -OutputDirectory $export}catch{$exportError=$_.Exception.Message}
Assert ($exportResult.Status -eq 'Passed' -and $exportResult.Count -eq 5) ('真export入口應保留版本2完整五包：'+$exportError)
Assert ((Test-SetupDriverPayload $h $export).Count -eq 5) '輸出包可離線獨立驗證版本2'
@($entries[0..3]|ForEach-Object {@{File=$_.File;SHA256=$_.SHA256}})|ConvertTo-Json|Set-Content (Join-Path $fixture 'manifest.json') -Encoding UTF8
Assert ((Test-SetupDriverPayload $h $fixture).Count -eq 4) '舊四檔格式仍可驗證'
Assert ((Test-SetupDriverPayload (Get-SetupHardwareProfile -BoardProduct Other) $fixture).Status -eq 'Skipped') '非NUC仍略過驅動'
Write-Host 'ALL PASS: 11 manifest assertions; TEMP only.'