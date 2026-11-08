#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$p=Join-Path $root 'modules/start_menu/start_pins_policy_library.ps1'
Assert (Test-Path $p) 'version capability and explicit late policy application are safely callable'
. $p
$admx='<policyDefinitions><policies><policy name="ConfigureStartPins" key="Software\Policies\Microsoft\Windows\Explorer" valueName="ConfigureStartPins"><elements><text valueName="ConfigureStartPinsJSON"/></elements></policy></policies></policyDefinitions>'
foreach($v in @(@(22621,9999),@(22631,9999),@(26100,4769))){Assert ((Get-StartPinsRoute $v[0] $v[1] $admx) -eq 'LegacyPackage') ('older build requires legacy route '+$v[0]+'.'+$v[1])}
Assert ((Get-StartPinsRoute 26100 4770 $admx) -eq 'Gpo') 'patched24H2 with real ADMX capability uses GPO'
Assert ((Get-StartPinsRoute 26200 1 '') -eq 'LegacyPackage') 'new build alone does not prove ADMX capability'
$script:installed=$false;$script:applied=0;$script:asked=0
function Assert-StartPinsAsset {param($AssetRoot);[pscustomobject]@{PackageId='73c18f23-529e-4379-a458-4c9b3a8d5b92';PackageName='windows_setup_empty_start';PackageVersion='1.0'}}
function Get-ProvisioningPackage {param([switch]$AllInstalledPackages,$ErrorAction);if($script:installed){[pscustomobject]@{PackageID='73c18f23-529e-4379-a458-4c9b3a8d5b92';PackageName='windows_setup_empty_start';Version='1.0';IsInstalled=$true}}}
function Install-ProvisioningPackage {param($PackagePath,[switch]$QuietInstall,$ErrorAction);$script:applied++;$script:installed=$true}
$yes={$script:asked++;'YES'}
$r=Invoke-StartPinsLegacyPolicy -AssetRoot $env:TEMP -Confirm $yes
Assert ($r.Status -eq 'LegacyPendingApply' -and $script:applied -eq 0 -and $script:asked -eq 0) 'ordinary module phase never asks or applies policy'
$r=Invoke-StartPinsLegacyPolicy -AssetRoot $env:TEMP -ApplyPolicy -NonInteractive -Confirm $yes
Assert ($r.Status -eq 'LegacyPendingApply' -and $script:applied -eq 0 -and $script:asked -eq 0) 'noninteractive never asks or installs'
$r=Invoke-StartPinsLegacyPolicy -AssetRoot $env:TEMP -ApplyPolicy -Confirm {'no'}
Assert ($r.Status -eq 'LegacyPendingApply' -and $script:applied -eq 0) 'decline retains pending with no install'
$r=Invoke-StartPinsLegacyPolicy -AssetRoot $env:TEMP -ApplyPolicy -Confirm $yes
Assert ($r.Status -eq 'PendingSignIn' -and -not $r.Success -and $script:applied -eq 1) 'explicit YES applies once but does not claim actual pins cleared'
$r=Invoke-StartPinsLegacyPolicy -AssetRoot $env:TEMP -ApplyPolicy -Confirm $yes
Assert ($script:applied -eq 1 -and $script:asked -eq 1) 'matching installed identity is not reapplied'
