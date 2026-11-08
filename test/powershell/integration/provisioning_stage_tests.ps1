#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
. (Join-Path $root 'modules/init/oobe_library.ps1')
. (Join-Path $root 'modules/init/provisioning_library.ps1')
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++}
Assert ([bool](Get-Command New-InitProvisioningStage -ErrorAction SilentlyContinue)) 'init stages self-contained runtime before account creation'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('init_stage_'+[guid]::NewGuid().ToString('N'));$source=Join-Path $temp 'source';$stage=Join-Path $temp 'stage'
foreach($name in @('modules/init/initialize_nuc.ps1','modules/init/oobe_library.ps1','modules/init/provisioning_library.ps1','modules/init/provisioning_asset_library.ps1','modules/init/assets/hide_oobe.xml','modules/init/assets/hide_oobe.ppkg','modules/init/assets/provenance.json','modules/ssh/apply_ssh_settings.ps1','modules/ssh/ssh_firewall.ps1','modules/ssh/custom_hosts_sync/ssh_readme.md')){
 $file=Join-Path $source $name;New-Item -ItemType Directory -Path (Split-Path $file) -Force|Out-Null;[IO.File]::WriteAllText($file,'synthetic fixture only')
}
$private=Join-Path $source 'modules/ssh/custom_hosts_sync/runtime.json';[IO.File]::WriteAllText($private,'must not copy')
$script:assetOK=$false;$script:protected=$false
function Assert-InitProvisioningAsset {param($AssetRoot) if(-not $script:assetOK){throw 'synthetic invalid asset'}}
function Protect-InitFolder {param($Path) $script:protected=$true}
function Assert-InitProtectedDirectory {param($Path) if(-not $script:protected){throw 'unprotected'}}
$rejected=$false;try{New-InitProvisioningStage $source $stage}catch{$rejected=$true}
Assert ($rejected -and -not(Test-Path $stage)) 'asset failure causes no stage creation'
$script:assetOK=$true
New-InitProvisioningStage $source $stage
Assert ($script:protected -and (Test-Path (Join-Path $stage 'runtime/modules/ssh/custom_hosts_sync/ssh_readme.md'))) 'stage contains nested SSH dependencies after ACL protection'
Assert (-not(Test-Path (Join-Path $stage 'runtime/modules/ssh/custom_hosts_sync/runtime.json'))) 'source machine state is never staged'
$launcher=[IO.File]::ReadAllText((Join-Path $stage 'resume_init.cmd'))
Assert ($launcher.Contains('%~dp0') -and -not $launcher.Contains($source)) 'resume launcher uses its own location, never original USB'
$rejected=$false;try{New-InitProvisioningStage $source $stage}catch{$rejected=$true}
Assert $rejected 'existing stage is not overwritten'
Write-Host ('ALL PASS: '+$script:count+' TEMP staging assertions; dummy files only')
