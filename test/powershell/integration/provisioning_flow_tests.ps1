#Requires -Version 5.1
$ErrorActionPreference='Stop'
. ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\modules\init\provisioning_library.ps1')))
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++}
Assert ([bool](Get-Command Invoke-InitOobeFlow -ErrorAction SilentlyContinue)) 'real OOBE flow validates context and assets before prompts or account creation'
$script:assetOK=$false;$script:accounts=0;$script:prompts=0;$script:staged=$false;$script:applied=$false
function Get-InitProvisioningContext { @{Sid='S-1-5-18';Build=22631;ProductType=1;Is64Bit=$true;IsWinPE=$false;OobeInProgress=1;SetupInProgress=1;OobeProcessInSession=$true;OobeApiSucceeded=$true;OobeComplete=$false;MachineGuid='fixture';ComputerName='TEST'} }
function Assert-InitProvisioningAsset {param($AssetRoot) if(-not $script:assetOK){throw 'synthetic missing package'};[pscustomobject]@{PackageSHA256=('e'*64)}}
function New-InitProvisioningStage {param($SourceRoot,$StageRoot) $script:staged=$true}
function Save-InitProvisioningState {param($State,$StatePath) if(-not $script:staged){throw 'not staged'}}
function Read-Host {param($Prompt,[switch]$AsSecureString) $script:prompts++;if(-not $script:staged){throw 'prompt before ACL stage'};if($AsSecureString){return (ConvertTo-SecureString 'test-pass' -AsPlainText -Force)};return 'fixture-user'}
function Get-LocalUser { @() }
function New-InitProvisioningAccount {param($State,$UserName,$Password,$StatePath) $script:accounts++;Assert ($Password -is [Security.SecureString]) 'flow passes SecureString to account function';$State.TargetSid='S-1-5-21-1-2-3-1001';$State.TargetUserName=$UserName;$State.Phase='AccountReady'}
function Invoke-InitProvisioningApply {param($State,$StatePath,$AssetRoot,$Confirm) $script:applied=$true}
$stage=Join-Path ([IO.Path]::GetTempPath()) ('not_created_'+[guid]::NewGuid().ToString('N'))
$rejected=$false;try{Invoke-InitOobeFlow (Join-Path ([IO.Path]::GetTempPath()) 'fixture_source') $stage}catch{$rejected=$true}
Assert ($rejected -and $script:accounts -eq 0 -and $script:prompts -eq 0 -and -not $script:staged) 'missing package causes zero prompts, staging or accounts'
$script:assetOK=$true
Invoke-InitOobeFlow (Join-Path ([IO.Path]::GetTempPath()) 'fixture_source') $stage
Assert ($script:accounts -eq 1 -and $script:prompts -eq 3 -and $script:applied) 'new flow stages then asks only username and password twice before applying'
Write-Host ('ALL PASS: '+$script:count+' safely mocked full OOBE flow assertions')
