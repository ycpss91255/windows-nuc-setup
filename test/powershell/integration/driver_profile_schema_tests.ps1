#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'));. (Join-Path $root 'core/hardware.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$d=[ordered]@{Id='parent';InfPath='parent.inf';HardwareIds=@('ROOT\AMDLOG');Provider='AMD';DriverVersion='23.10.0.6';Architecture='amd64';MinimumBuild=22000}
$e=[ordered]@{Id='extension';Kind='Extension';ParentTarget='parent';InfPath='ext.inf';CatalogPath='ext.cat';InfSHA256=('A'*64);CatalogSHA256=('B'*64);HardwareIds=@('PCI\VEN_1002&DEV_694C');Provider='AMD';DriverVersion='1.0.0.0';Architecture='amd64';MinimumBuild=22000;ExtensionId='{07A2A561-D001-4503-B239-EF2FE0379EFB}';ActiveAssociationRequired=$true}
$m=[ordered]@{SchemaVersion=2;Packages=@([ordered]@{Id='example';File='test.zip';SHA256=('C'*64);SourceUrl='https://www.intel.com/driver';PackageVersion='1.0';Drivers=@($d);Extensions=@($e);ScopeTarget='parent'})}
Assert (@(Get-SetupDriverManifestEntries $m).Count -eq 1) '明確AMDLOG與有父裝置的extension可解析'
foreach($case in @('RootWildcard','MissingParent','BadGuid','BadInfHash','BadCatHash','CatTraversal','NoActiveAssociation','UnknownScope','UnknownTargetScope','NonSwcChild')){
 $copy=$m|ConvertTo-Json -Depth 15|ConvertFrom-Json
 switch($case){
 RootWildcard{$copy.Packages[0].Drivers[0].HardwareIds=@('ROOT\OTHER')}
 MissingParent{$copy.Packages[0].Extensions[0].ParentTarget='missing'}
 BadGuid{$copy.Packages[0].Extensions[0].ExtensionId='not-a-guid'}
 BadInfHash{$copy.Packages[0].Extensions[0].InfSHA256='bad'}
 BadCatHash{$copy.Packages[0].Extensions[0].CatalogSHA256='bad'}
 CatTraversal{$copy.Packages[0].Extensions[0].CatalogPath='../ext.cat'}
 NoActiveAssociation{$copy.Packages[0].Extensions[0].ActiveAssociationRequired=$false}
 UnknownScope{$copy.Packages[0].ScopeTarget='missing'}
 UnknownTargetScope{$copy.Packages[0].Drivers[0]|Add-Member NoteProperty ScopeParentTarget 'missing'}
 NonSwcChild{$child=$d|ConvertTo-Json|ConvertFrom-Json;$child.Id='child';$child|Add-Member NoteProperty ParentTarget 'parent';$child|Add-Member NoteProperty PreStage $true;$copy.Packages[0].Drivers+=@($child)}
 }
 $failed=$false;try{Get-SetupDriverManifestEntries $copy|Out-Null}catch{$failed=$true};Assert $failed ('拒絕不可信依賴或extension：'+$case)
}
Write-Host 'ALL PASS: extension schema safety; no host changes.'