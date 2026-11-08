param([switch]$VerifyOnly,[string]$VerificationRunId,[string]$Mode)
$fixtureRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
if($env:ProgramData -notlike ($fixtureRoot+'verify_aggregate_*')){throw 'This fixture may only run in its isolated TEMP tree.'}
if($global:AggregateFixtureMode -eq 'Throw'){throw 'fixture submodule failed'}
if([IO.Path]::GetFileName($PSCommandPath) -eq 'apply_start_menu_settings.ps1'){[pscustomobject]@{Success=($global:AggregateFixtureMode -ne 'False');Status=$(if($global:AggregateFixtureMode -eq 'False'){'PendingSignIn'}else{'Confirmed'});PinCount=$(if($global:AggregateFixtureMode -eq 'False'){1}else{0})};return}
if(-not $VerificationRunId -or $global:AggregateFixtureMode -eq 'Missing'){return}
$names=@{'apply_uac_settings.ps1'='UAC-Result.json';'apply_privacy_settings.ps1'='Privacy-Result.json';'apply_display_settings.ps1'='Display-Verification.json';'apply_theme_settings.ps1'='Theme-Verification.json';'desktop_icon_layout.ps1'='IconLayout-Result.json';'apply_pagefile_settings.ps1'='Pagefile-Result.json'}
$path=Join-Path (Join-Path $env:ProgramData 'NUC8-Setup') $names[[IO.Path]::GetFileName($PSCommandPath)]
$id=if($global:AggregateFixtureMode -eq 'Stale'){'old-id'}else{$VerificationRunId}
$computer=if($global:AggregateFixtureMode -eq 'WrongComputer'){'different-computer'}else{$env:COMPUTERNAME}
$user=if($global:AggregateFixtureMode -eq 'WrongUser'){'different-user'}else{[Security.Principal.WindowsIdentity]::GetCurrent().User.Value}
@{VerificationRunId=$id;Computer=$computer;UserSID=$user;Success=($global:AggregateFixtureMode -ne 'False');ActivePagefiles=@();DiagnosticLevel=1}|ConvertTo-Json|Set-Content $path -Encoding UTF8
