#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
. (Join-Path $root 'core/gui_stage_library.ps1')
Assert ([bool](Get-Command Invoke-SetupGuiFreshVerification -CommandType Function -ErrorAction SilentlyContinue)) 'fresh GUI verification has a bounded direct-return adapter instead of a public JSON reader'
$script:scope=[pscustomobject]@{UserSID='S-1-5-21-1-2-3-1001';Computer='fixture';SessionId=0}
$script:mode='Pass';$script:calls=@()
function Get-SetupGuiIdentity {$script:scope}
function Invoke-SetupGuiRole {param($PackageRoot,$Role,[switch]$VerifyOnly,[string]$VerificationRunId)
 $script:calls+=@([pscustomobject]@{Root=$PackageRoot;Role=$Role;VerifyOnly=[bool]$VerifyOnly;RunId=$VerificationRunId})
 $r=[pscustomobject]@{Schema=1;Role=$Role;RunId=$VerificationRunId;Computer=$script:scope.Computer;UserSID=$script:scope.UserSID;SessionId=4;VerifyOnly=[bool]$VerifyOnly;Success=$true}
 switch($script:mode){Stale{$r.RunId=[guid]::NewGuid().ToString('D')}WrongRole{$r.Role='Explorer'}WrongUser{$r.UserSID='S-1-5-21-1-2-3-1002'}WrongComputer{$r.Computer='other'}WrongSession{$r.SessionId=0}Apply{$r.VerifyOnly=$false}Malformed{$r.Success='true'}Failed{$r.Success=$false}Throw{throw 'fixture native verification failure'}}
 return $r
}
foreach($role in @('Display','Theme')){
 $r=Invoke-SetupGuiFreshVerification -PackageRoot $root -Role $role
 $call=$script:calls[-1];$guid=[guid]::Empty
 Assert ($call.Root -ceq $root -and $call.Role -ceq $role -and $call.VerifyOnly -and [guid]::TryParse($call.RunId,[ref]$guid) -and $r.RunId -ceq $call.RunId -and $r.Success) ('fresh '+$role+' binds an independently generated GUID to direct protected VerifyOnly invocation')
}
Assert ($script:calls[0].RunId -cne $script:calls[1].RunId) 'separate fresh verification calls never reuse a run identity'
foreach($mode in @('Stale','WrongRole','WrongUser','WrongComputer','WrongSession','Apply','Malformed','Throw')){
 $script:mode=$mode;$failure='';try{Invoke-SetupGuiFreshVerification -PackageRoot $root -Role Display|Out-Null}catch{$failure=$_.Exception.Message}
 Assert ([bool]$failure) ('fresh GUI direct result rejects '+$mode)
}
$script:mode='Failed';$r=Invoke-SetupGuiFreshVerification -PackageRoot $root -Role Display
Assert (-not $r.Success) 'a valid bound failed result remains false instead of being converted to success'
$script:mode='Pass';$script:scope.SessionId=4;$r=Invoke-SetupGuiFreshVerification -PackageRoot $root -Role Theme
Assert $r.Success 'matching interactive caller session can read a fresh bound result'
$script:scope.SessionId=8;$failure='';try{Invoke-SetupGuiFreshVerification -PackageRoot $root -Role Theme|Out-Null}catch{$failure=$_.Exception.Message}
Assert ([bool]$failure) 'interactive fresh verification cannot accept another desktop session'
$before=$script:calls.Count;$failure='';try{Invoke-SetupGuiFreshVerification -PackageRoot $root -Role Unapproved|Out-Null}catch{$failure=$_.Exception.Message}
Assert ([bool]$failure -and $script:calls.Count -eq $before) 'fresh adapter cannot select arbitrary roles or source scripts'
