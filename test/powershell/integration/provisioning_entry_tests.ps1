#Requires -Version 5.1
$ErrorActionPreference='Stop'
. ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\modules\init\provisioning_library.ps1')))
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++}
Assert ([bool](Get-Command Invoke-InitProvisioningEntry -ErrorAction SilentlyContinue)) 'init routes SYSTEM OOBE and staged formal-user continuation'
$script:sid='S-1-5-18';$script:oobeCalls=0;$script:sshCalls=0
function Get-InitProvisioningContext { @{Sid=$script:sid;IsAdministrator=$true;MachineGuid='fixture';ProfilePath=$env:USERPROFILE;RegisteredProfile=$env:USERPROFILE;DesktopOwned=$true;ImageState='IMAGE_STATE_COMPLETE'} }
function Invoke-InitOobeFlow {param($SourceRoot,$StageRoot) $script:oobeCalls++}
function Test-Path {param($LiteralPath,$Path,$PathType) $true}
function Assert-InitProtectedDirectory {param($Path)}
function Assert-InitProvisioningAsset {param($AssetRoot) [pscustomobject]@{PackageSHA256=('a'*64)}}
function Read-InitProvisioningState {param($StatePath,$MachineGuid,$PackageHash) $s=New-InitProvisioningState 'fixture' 'TEST' 'removed USB' ('a'*64);$s.TargetSid=$script:sid;$s.TargetUserName='fixture';$s.Phase='SshPending';return $s}
function Invoke-InitSshContinuation {param($State,$StatePath,$Context,$SshScriptPath) $script:sshCalls++;$script:sshPath=$SshScriptPath}
$root=Join-Path ([IO.Path]::GetTempPath()) 'fixture_entry'
Assert (Invoke-InitProvisioningEntry $root $root) 'SYSTEM route is handled by safe OOBE flow'
Assert ($script:oobeCalls -eq 1 -and $script:sshCalls -eq 0) 'SYSTEM cannot initialize user SSH profile'
$script:sid='S-1-5-21-1-2-3-1001'
$rejected=$false;try{Invoke-InitProvisioningEntry $root $root (Join-Path $root 'state.json') 'other-sid'}catch{$rejected=$true}
Assert ($rejected -and $script:sshCalls -eq 0) 'UAC account change rejects before reading resume data'
Assert (Invoke-InitProvisioningEntry $root $root (Join-Path $root 'state.json') $script:sid) 'formal user resumes from protected stage'
Assert ($script:sshCalls -eq 1 -and $script:sshPath -eq (Join-Path $root 'runtime/modules/ssh/apply_ssh_settings.ps1')) 'resume calls staged real SSH module path independent of USB'
Write-Host ('ALL PASS: '+$script:count+' safe entry assertions')
