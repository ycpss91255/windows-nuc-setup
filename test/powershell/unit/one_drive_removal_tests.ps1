#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$library=Join-Path $root 'modules/debloat/one_drive_library.ps1'
Assert (Test-Path $library) 'OneDrive removal has safely callable postcondition logic'
. $library
$script:removed=$false;$script:residual=$false;$script:code=-2147219813;$script:started=0
function Get-OneDriveRemovalState {
 if(-not $script:removed){return [pscustomobject]@{Entries=@([pscustomobject]@{UninstallString='"C:\Program Files\OneDriveSetup.exe" /uninstall'});ExecutableCount=1;ProcessCount=0;VerifiedAbsent=$false}}
 [pscustomobject]@{Entries=@();ExecutableCount=$(if($script:residual){1}else{0});ProcessCount=0;VerifiedAbsent=(-not $script:residual)}
}
function Get-AuthenticodeSignature {param($LiteralPath,$ErrorAction);[pscustomobject]@{Status='Valid';SignerCertificate=[pscustomobject]@{Subject='O=Microsoft Corporation'}}}
function Start-Process {param($FilePath,$ArgumentList,[switch]$PassThru);$script:started++;$script:removed=$true;$p=[pscustomobject]@{ExitCode=$script:code};$p|Add-Member ScriptMethod WaitForExit {param($milliseconds);return $true};return $p}
function Start-Sleep {param($Seconds)}
$r=Invoke-OneDriveRemoval
Assert ($r.Success -and $r.VerifiedAbsent -and $r.ExitCodes[0] -eq -2147219813) 'nonzero uninstaller plus verified absent permits caller to continue'
$script:removed=$false;$script:residual=$true;$r=Invoke-OneDriveRemoval
Assert (-not $r.Success -and -not $r.VerifiedAbsent -and $r.RemainingExecutables -eq 1) 'same exit code with remaining executable is failure'
$script:removed=$false;$script:code=0;$r=Invoke-OneDriveRemoval
Assert (-not $r.Success) 'zero exit does not override actual remaining installation'
$before=$script:started;$script:removed=$true;$script:residual=$false;$r=Invoke-OneDriveRemoval -VerifyOnly
Assert ($r.Success -and $script:started -eq $before) 'verify-only never invokes uninstaller'
function Get-OneDriveRemovalState {throw 'read access denied'}
$failed=$false;try{Invoke-OneDriveRemoval}catch{$failed=$true}
Assert $failed 'unreadable postconditions never become success'
