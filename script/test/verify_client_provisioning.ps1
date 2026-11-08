#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $root 'modules\init\provisioning_library.ps1')
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++}
Assert ([bool](Get-Command Assert-InitProvisioningAsset -ErrorAction SilentlyContinue)) 'init validates static package before account creation'
$assets=Join-Path $root 'modules\init\assets'
$manifest=Assert-InitProvisioningAsset -AssetRoot $assets
Assert ($manifest.PackageName -eq 'windows_setup_hide_oobe' -and $manifest.PackageVersion -eq '1.0') 'production package has stable identity'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('init_asset_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp|Out-Null
foreach($name in @('hide_oobe.ppkg','hide_oobe.xml','provenance.json')){Copy-Item -LiteralPath (Join-Path $assets $name) -Destination $temp}
foreach($name in @('hide_oobe.ppkg','hide_oobe.xml')){
 $path=Join-Path $temp $name;$bytes=[IO.File]::ReadAllBytes($path)
 [IO.File]::AppendAllText($path,'corrupt')
 $rejected=$false;try{Assert-InitProvisioningAsset -AssetRoot $temp}catch{$rejected=$true}
 Assert $rejected ('reject changed '+$name+' before accounts')
 [IO.File]::WriteAllBytes($path,$bytes)
}
$metadata=@(Get-ProvisioningPackage -PackagePath (Join-Path $assets 'hide_oobe.ppkg') -LogsDirectoryPath (Join-Path $temp 'logs')|Where-Object {$_.PackageID})
Assert ($metadata.Count -eq 1 -and $metadata[0].PackageID -eq $manifest.PackageId -and $metadata[0].PackageName -eq $manifest.PackageName -and $metadata[0].Version -eq $manifest.PackageVersion) 'real Windows read-only package metadata matches provenance'
Assert (-not $metadata[0].IsInstalled) 'read-only metadata does not install package'
Write-Host ('ALL PASS: '+$script:count+' read-only package assertions')
