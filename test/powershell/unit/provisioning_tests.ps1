#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$library=Join-Path $root 'modules\init\provisioning_library.ps1'
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++}
Assert (Test-Path -LiteralPath $library) 'OOBE provisioning has a safely loadable implementation'
. $library
$good=@{Sid='S-1-5-18';Build=22631;ProductType=1;Is64Bit=$true;IsWinPE=$false;OobeInProgress=1;SetupInProgress=1;OobeProcessInSession=$true}
Assert (Test-InitProvisioningContext @good) 'Windows 11 client SYSTEM in actual OOBE is accepted'
foreach($field in @('Sid','Build','ProductType','Is64Bit','IsWinPE','OobeInProgress','SetupInProgress','OobeProcessInSession')){
 $bad=$good.Clone();$bad[$field]=switch($field){Sid {'S-1-5-21-1-2-3-1001'} Build {19045} ProductType {3} IsWinPE {$true} default {0}}
 Assert (-not(Test-InitProvisioningContext @bad)) ('reject context mismatch: '+$field)
}
$state=New-InitProvisioningState -MachineGuid 'test-machine' -ComputerName 'TEST' -SourceRoot 'Q:\arbitrary\setup' -PackageHash ('a'*64)
Assert ($state.SchemaVersion -eq 1 -and $state.Phase -eq 'Prepared') 'state begins before account creation'
Assert ($state.MachineGuid -eq 'test-machine' -and -not $state.TargetSid) 'state binds machine before creating account'
Assert (@($state.PSObject.Properties.Name|Where-Object {$_ -match 'password|credential|secret'}).Count -eq 0) 'state schema has no credential fields'
Assert-InitProvisioningState -State $state -MachineGuid 'test-machine' -PackageHash ('a'*64)
foreach($field in @('MachineGuid','PackageHash')){
 $args=@{State=$state;MachineGuid='test-machine';PackageHash=('a'*64)};$args[$field]='mismatch'
 $rejected=$false;try{Assert-InitProvisioningState @args}catch{$rejected=$true}
 Assert $rejected ('resume rejects changed '+$field)
}
$state|Add-Member NoteProperty Password 'forbidden'
$rejected=$false;try{Assert-InitProvisioningState $state 'test-machine' ('a'*64)}catch{$rejected=$true}
Assert $rejected 'state refuses unknown fields rather than persisting credentials'
Write-Host ('ALL PASS: '+$script:count+' provisioning unit assertions')
