#Requires -Version 5.1
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $repo 'modules/start_menu/start_pins_policy_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
Assert ([bool](Get-Command Complete-StartPinsPending -ErrorAction SilentlyContinue)) 'late pending policy has safely callable completion gate'
$pending=[pscustomobject]@{Success=$false;Status='LegacyPendingApply'};$script:calls=0
$apply={param([switch]$ApplyPolicy,[switch]$NonInteractive);if(-not $ApplyPolicy -or $NonInteractive){throw 'wrong flags'};$script:calls++;[pscustomobject]@{Success=$false;Status='PendingSignIn'}}
foreach($options in @(@{StageErrors=@('failed')},@{ProblemCount=1},@{NonInteractive=$true})){
 $r=Complete-StartPinsPending -Result $pending -Apply $apply @options
 Assert ($script:calls -eq 0 -and $r.Status -eq 'LegacyPendingApply') 'errors devices and noninteractive retain pending without policy installation'
}
$r=Complete-StartPinsPending -Result $pending -Apply $apply
Assert ($script:calls -eq 1 -and -not $r.Success -and $r.Status -eq 'PendingSignIn') 'eligible late call requests explicit module confirmation and preserves pending result'
$r=Complete-StartPinsPending -Result $r -Apply $apply
Assert ($script:calls -eq 1) 'sign-in pending never reapplies policy'
$r=Complete-StartPinsPending -Result $pending -Apply {param([switch]$ApplyPolicy);[pscustomobject]@{Success=$false;Status='LegacyPendingApply'}}
Assert (-not $r.Success -and $r.Status -eq 'LegacyPendingApply') 'decline remains pending rather than completed'
$failed=$false;try{Complete-StartPinsPending -Result $pending -Apply {throw 'native failure'}}catch{$failed=$true}
Assert $failed 'native apply failure propagates to controller error record'
