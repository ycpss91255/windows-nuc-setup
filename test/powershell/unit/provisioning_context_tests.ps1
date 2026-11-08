#Requires -Version 5.1
$ErrorActionPreference='Stop'
. ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\modules\init\provisioning_library.ps1')))
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++}
Assert ([bool](Get-Command Get-InitProvisioningContext -ErrorAction SilentlyContinue)) 'context collector reads registry and session ownership'
$script:sid='S-1-5-18';$script:session=7;$script:otherSession=$false
$script:apiSuccess=$true;$script:apiComplete=$false
function Invoke-InitOobeCompleteNative { [pscustomobject]@{Succeeded=$script:apiSuccess;Complete=$script:apiComplete;ErrorCode=5} }
function Get-InitIdentityContext { @{Sid=$script:sid;IsAdministrator=$true;SessionId=7} }
function Get-ItemProperty {param($LiteralPath,$Path,$ErrorAction)
 $p=if($LiteralPath){$LiteralPath}else{$Path}
 switch -Wildcard ($p){
  '*Cryptography' {[pscustomobject]@{MachineGuid='fixture-machine'}}
  '*Setup\State' {[pscustomobject]@{ImageState='IMAGE_STATE_UNDEPLOYABLE'}}
  '*ProfileList*' {[pscustomobject]@{ProfileImagePath=$env:USERPROFILE}}
  default {[pscustomobject]@{OOBEInProgress=1;SystemSetupInProgress=1}}
 }
}
function Test-Path {param($LiteralPath,$Path) $false}
function Get-CimInstance {param($ClassName,$Filter,$ErrorAction)
 if($ClassName -eq 'Win32_OperatingSystem'){return [pscustomobject]@{BuildNumber=22631;ProductType=1}}
 [pscustomobject]@{Name='msoobe.exe';SessionId=$(if($script:otherSession){8}else{7})}
 [pscustomobject]@{Name='explorer.exe';SessionId=7}
}
function Invoke-CimMethod {param($InputObject,$MethodName,$ErrorAction) [pscustomobject]@{ReturnValue=0;Sid=$script:sid}}
$context=Get-InitProvisioningContext
Assert ($context.OobeProcessInSession -and $context.MachineGuid -eq 'fixture-machine' -and $context.Sid -eq 'S-1-5-18') 'collector correlates OOBE process with current session'
Assert (-not $context.DesktopOwned -and -not $context.RegisteredProfile) 'SYSTEM never becomes a formal user profile'
$script:otherSession=$true
Assert (-not (Get-InitProvisioningContext).OobeProcessInSession) 'OOBE process from another session is insufficient'
$script:sid='S-1-5-21-1-2-3-1001'
$context=Get-InitProvisioningContext
Assert ($context.DesktopOwned -and $context.RegisteredProfile -eq $env:USERPROFILE) 'formal profile comes from SID registry and Explorer owner'
$script:apiSuccess=$false
$context=Get-InitProvisioningContext
Assert (-not $context.OobeApiSucceeded) 'native BOOL failure cannot be treated as incomplete OOBE'
$script:apiSuccess=$true;$script:apiComplete=$true
$context=Get-InitProvisioningContext
Assert ($context.OobeApiSucceeded -and $context.OobeComplete) 'native success and completed output are distinct facts'
Write-Host ('ALL PASS: '+$script:count+' collector command-mock assertions')
