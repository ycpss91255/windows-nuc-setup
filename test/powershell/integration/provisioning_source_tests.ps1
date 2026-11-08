#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
. (Join-Path $root 'modules\init\provisioning_library.ps1')
# CI models the real Server runner: this client-only API must not be used by source tests.
function Get-ProvisioningPackage {throw (New-Object Management.Automation.CommandNotFoundException('Windows Server source test has no client provisioning API'))}
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++}
Assert ([bool](Get-Command Assert-InitProvisioningAssetSource -ErrorAction SilentlyContinue)) 'CI validates real source assets independently of native client metadata'
$assets=Join-Path $root 'modules\init\assets'
$manifest=Assert-InitProvisioningAssetSource -AssetRoot $assets
Assert ($manifest.PackageName -eq 'windows_setup_hide_oobe' -and $manifest.PackageVersion -eq '1.0') 'production package has stable identity'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('init_asset_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temp|Out-Null
foreach($name in @('hide_oobe.ppkg','hide_oobe.xml','provenance.json')){Copy-Item -LiteralPath (Join-Path $assets $name) -Destination $temp}
foreach($name in @('hide_oobe.ppkg','hide_oobe.xml')){
 $path=Join-Path $temp $name;$bytes=[IO.File]::ReadAllBytes($path)
 [IO.File]::AppendAllText($path,'corrupt')
 $rejected=$false;try{Assert-InitProvisioningAssetSource -AssetRoot $temp}catch{$rejected=$true}
 Assert $rejected ('reject changed '+$name+' before accounts')
 [IO.File]::WriteAllBytes($path,$bytes)
}
Write-Host ('ALL PASS: '+$script:count+' real source/hash/XML assertions; native metadata is a separate Windows 11 client check')
