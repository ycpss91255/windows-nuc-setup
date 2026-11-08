#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/start_menu/start_pins_policy_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$script:code=-2147023728;$script:hostPresent=$false
function Export-StartLayout {param($Path,$ErrorAction);throw (New-Object Runtime.InteropServices.COMException('synthetic unrelated localized message',$script:code))}
function Get-Process {param($Id,$ErrorAction);if($Id){return [pscustomobject]@{SessionId=4}};if($script:hostPresent){[pscustomobject]@{ProcessName='StartMenuExperienceHost';SessionId=4}}}
$r=$null;$errorText='';try{$r=Get-StartPinsExportState 'unused.json' ([pscustomobject]@{Status='PendingSignIn';PolicyInstalled=$true})}catch{$errorText=$_.Exception.Message}
Assert ($r -and -not $r.Success -and $r.Status -eq 'PendingSignIn' -and $null -eq $r.PinCount -and $r.NativeHResult -eq '0x80070490') ('known native unavailable export remains pending, never empty success; '+$errorText)
$script:hostPresent=$true;$failed=$false;try{Get-StartPinsExportState 'unused.json' ([pscustomobject]@{Status='PendingSignIn';PolicyInstalled=$true})}catch{$failed=$true}
Assert $failed 'same native error with ready host is not silently hidden'
$script:hostPresent=$false;$script:code=-2147024891;$failed=$false;try{Get-StartPinsExportState 'unused.json' ([pscustomobject]@{Status='PendingSignIn';PolicyInstalled=$true})}catch{$failed=$true}
Assert $failed 'access denied remains a failure even without host'
$script:code=-2147023728;$failed=$false;try{Get-StartPinsExportState 'unused.json' ([pscustomobject]@{Status='LegacyPendingApply';PolicyInstalled=$false})}catch{$failed=$true}
Assert $failed 'missing policy cannot be reported as waiting for sign-in'
function Get-Process {param($Id,$ErrorAction);throw 'process inspection denied'}
$failed=$false;try{Get-StartPinsExportState 'unused.json' ([pscustomobject]@{Status='PendingSignIn';PolicyInstalled=$true})}catch{$failed=$true}
Assert $failed 'unreadable host readiness is never treated as absent'
