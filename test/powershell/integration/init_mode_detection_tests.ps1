#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/init/init_entry_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$script:prompts=@();$script:writes=0
function Invoke-InitProvisioningEntry {return $false}
function Get-SetupInitContext {
 [pscustomobject]@{Sid='S-1-5-21-1-2-3-500';UserSID='S-1-5-21-1-2-3-500';IsAdministrator=$true;Is64Bit=$true;Architecture='AMD64';ImageState='IMAGE_STATE_UNDEPLOYABLE';DesktopOwned=$true;ModeFacts=@{ReadSucceeded=$true;Build=26200;ProductType=1;IsWinPE=$false;OobeApiSucceeded=$true;OobeComplete=$false;AuditBoot=1;SetupInProgress=0;OobeInProgress=0;OobeProcessInSession=$false;ProfileMatches=$true}}
}
function Get-Process {return @()}
function Get-ItemProperty {return [pscustomobject]@{SkuPolicyRequired=0;UnattendFile=$null}}
function Test-Path {param($LiteralPath,$Path,$PathType);return [bool]($LiteralPath -like '*Sysprep.exe')}
function Read-Host {param($Prompt,[switch]$AsSecureString);$script:prompts+=@($Prompt);return 'NO'}
function New-Item {$script:writes++;throw 'SAFE_MUTATION_SENTINEL'}
function Start-Process {$script:writes++;throw 'SAFE_NATIVE_SENTINEL'}
function New-LocalUser {$script:writes++;throw 'SAFE_ACCOUNT_SENTINEL'}
function Get-LocalUser {throw 'credentials must not be collected before consent'}
$rejected=$false;try{Invoke-SetupInit -EntryPath (Join-Path $root 'modules/init/initialize_nuc.ps1') -ModuleRoot (Join-Path $root 'modules/init')}catch{$rejected=$true}
Write-Host ('MODE_PROMPTS='+@($script:prompts|Where-Object {$_ -cmatch 'AUDIT'}).Count)
Assert (@($script:prompts|Where-Object {$_ -cmatch 'AUDIT'}).Count -eq 0) 'current Audit mode is derived from facts without requesting typed AUDIT'
Assert ($rejected -and $script:prompts.Count -eq 1 -and $script:prompts[0] -match 'YES' -and $script:writes -eq 0) 'declining distinct account OOBE consent stops before credentials or any mutation'