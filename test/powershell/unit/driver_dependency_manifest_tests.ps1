#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../../core/hardware.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$p=@{Id='parent';InfPath='parent.inf';DriverVersion='2.0.0.0';Provider='Intel';Architecture='amd64';MinimumBuild=22000;HardwareIds=@('PCI\VEN_8086&DEV_A13A')}
$c=@{Id='child';ParentTarget='parent';PreStage=$true;InfPath='child.inf';DriverVersion='1.41.2021.0121';Provider='Intel';Architecture='amd64';MinimumBuild=22000;HardwareIds=@('SWC\3C4852D6-D47B-4F46-B05E-B5EDC1AA440E')}
$m=@{SchemaVersion=2;Packages=@(@{Id='mei';File='mei.zip';SHA256=('A'*64);PackageVersion='11.8.93.4323';SourceUrl='https://www.intel.com/driver';Drivers=@($p,$c)})}
$json=$m|ConvertTo-Json -Depth 10
$message='';try{$entries=@(Get-SetupDriverManifestEntries -Manifest ($json|ConvertFrom-Json))}catch{$message=$_.Exception.Message}
Assert (-not $message -and $entries.Count -eq 1) ('清單可表達已核SWC精確ID與父裝置關係：'+$message)
foreach($case in @('unknown_parent','self_parent','duplicate_id','nested_cycle','not_prestaged')){
 $bad=$json|ConvertFrom-Json
 switch($case){unknown_parent{$bad.Packages[0].Drivers[1].ParentTarget='other'} self_parent{$bad.Packages[0].Drivers[1].ParentTarget='child'} duplicate_id{$bad.Packages[0].Drivers[1].Id='parent'} nested_cycle{$bad.Packages[0].Drivers[0]|Add-Member ParentTarget 'child';$bad.Packages[0].Drivers[0]|Add-Member PreStage $true} not_prestaged{$bad.Packages[0].Drivers[1].PreStage=$false}}
 $rejected=$false;try{Get-SetupDriverManifestEntries -Manifest $bad|Out-Null}catch{$rejected=$true}
 Assert $rejected ('不安全或不完整的依賴圖拒絕：'+$case)
}
