#Requires -Version 5.1
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'core/verification_library.ps1'),[ref]$t,[ref]$e)
$check=$ast.FindAll({param($a) $a -is [Management.Automation.Language.TryStatementAst] -and $a.Extent.Text.Contains("Resolve-NucPath 'apply_start_menu_settings.ps1'")},$true)|Select-Object -Last 1
$fixture=Join-Path $env:TEMP ('start_verify_'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory $fixture
$entry=Join-Path $fixture 'start.ps1';[IO.File]::WriteAllText($entry,'param([switch]$VerifyOnly,[switch]$ApplyPolicy);if(-not $VerifyOnly -or $ApplyPolicy){throw "verification attempted mutation"};$global:startVerifiedCall=$true;$global:startVerificationFixture')
function Resolve-NucPath {param($Name) $entry}
function Add-Check {param($Name,$Passed,$Detail) $script:passed=$Passed}
foreach($status in @('PendingSignIn','LegacyPendingApply','ConfirmedBad','Confirmed')){
 $global:startVerificationFixture=[pscustomobject]@{Success=($status -like 'Confirmed*');Status=$(if($status -like 'Confirmed*'){'Confirmed'}else{$status});PinCount=$(if($status -eq 'Confirmed'){0}else{1})}
 & ([scriptblock]::Create($check.Extent.Text))
 Assert ($script:passed -eq ($status -eq 'Confirmed')) ('actual aggregate checks native result instead of absence of throw '+$status)
}
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'core/after_restart_library.ps1'),[ref]$t,[ref]$e)
$retry=$ast.FindAll({param($a) $a -is [Management.Automation.Language.TryStatementAst] -and $a.Extent.Text.Contains("if(`$file -eq 'install_drivers.ps1')")},$true)|Select-Object -First 1
$file='apply_start_menu_settings.ps1';$errors=@();$remaining=@();$global:startVerifiedCall=$false
& ([scriptblock]::Create($retry.Extent.Text))
Assert ($global:startVerifiedCall) 'AfterRestart Start retry only verifies and cannot apply policy'
