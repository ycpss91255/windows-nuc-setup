#Requires -Version 5.1
$ErrorActionPreference='Stop'
. ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\modules\init\provisioning_library.ps1')))
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++}
Assert ([bool](Get-Command Invoke-InitProvisioningApply -ErrorAction SilentlyContinue)) 'package application has an explicit consent orchestration'
$state=New-InitProvisioningState 'fixture' 'TEST' 'Q:\source' ('d'*64)
$state.TargetSid='S-1-5-21-1-2-3-1001';$state.TargetUserName='fixture';$state.Phase='AccountReady'
$script:calls=0;$script:installed=$false;$script:assetValid=$true;$script:consents=0;$script:saved='';$script:interrupt=$false
function Assert-InitProvisioningAsset {param($AssetRoot) if(-not $script:assetValid){throw 'synthetic tamper'};return [pscustomobject]@{PackageSHA256=('d'*64)}}
function Save-InitProvisioningState {param($State,$StatePath) $script:saved=$State.Phase}
function Get-LocalUser {param($SID,$ErrorAction) [pscustomobject]@{Name='fixture';SID=[pscustomobject]@{Value=$state.TargetSid};Enabled=$true}}
function Get-LocalGroupMember {param($SID,$ErrorAction) [pscustomobject]@{SID=[pscustomobject]@{Value=$state.TargetSid}}}
function Get-ProvisioningPackage {param($AllInstalledPackages,$LogsDirectoryPath,$ErrorAction) if($script:installed){[pscustomobject]@{IsInstalled=$true;PackageID=$state.PackageId;Version='1.0';PackageName='windows_setup_hide_oobe'}}}
function Install-ProvisioningPackage {param($PackagePath,[switch]$QuietInstall,$LogsDirectoryPath,$ErrorAction) Assert ($script:saved -eq 'ApplyPending') 'pending state is persisted before package application';$script:calls++;$script:installed=$true;if($script:interrupt){throw 'synthetic interrupted response'}}
$decline={$script:consents++;return $false}
Invoke-InitProvisioningApply $state 'unused' 'fixture_assets' $decline
Assert ($script:calls -eq 0 -and $state.Phase -eq 'AwaitingConsent') 'decline preserves account and performs no package application'
$script:assetValid=$false
$rejected=$false;try{Invoke-InitProvisioningApply $state 'unused' 'fixture_assets' $decline}catch{$rejected=$true}
Assert ($rejected -and $script:consents -eq 1 -and $script:calls -eq 0) 'corrupt asset rejected before consent and mutation'
$script:assetValid=$true;$script:interrupt=$true
$rejected=$false;try{Invoke-InitProvisioningApply $state 'unused' 'fixture_assets' {return $true}}catch{$rejected=$true}
Assert ($rejected -and $state.Phase -eq 'ApplyPending' -and $script:calls -eq 1) 'interrupted apply retains pending for read-back recovery'
Invoke-InitProvisioningApply $state 'unused' 'fixture_assets' {throw 'should not prompt again'}
Assert ($state.Phase -eq 'AwaitingLogon' -and $script:calls -eq 1) 'installed metadata recovers interrupted apply without reapplying'
Write-Host ('ALL PASS: '+$script:count+' safe mocked provisioning assertions')
