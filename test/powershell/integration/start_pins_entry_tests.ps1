#Requires -Version 5.1
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
function Parse($File){$t=$null;$e=$null;[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo $File),[ref]$t,[ref]$e)}
$ast=Parse 'core/run_module.ps1'
Assert ($ast.ParamBlock.Parameters.Name.VariablePath.UserPath -contains 'ApplyPolicy') 'standalone accepts explicit policy confirmation mode'
$fixture=Join-Path $env:TEMP ('start_entry_'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory $fixture
$entry=Join-Path $fixture 'entry.ps1';[IO.File]::WriteAllText($entry,'param($Module,$ExpectedUserSID,[switch]$ApplyPolicy,[switch]$NonInteractive,[switch]$VerifyOnly);[pscustomobject]@{Apply=$ApplyPolicy.IsPresent;Quiet=$NonInteractive.IsPresent;Verify=$VerifyOnly.IsPresent}')
function Start-Process {param($FilePath,$Verb,$ArgumentList);$script:captured=$ArgumentList}
$Module='Apply-StartMenuSettings';$ApplyPolicy=$true;$NonInteractive=$true;$VerifyOnly=$false;$Restore=$false;$sid='fixture';$Mode='All';$ConfirmedBoard='';$PSCommandPath=$entry
$elevation=$ast.Find({param($a) $a -is [Management.Automation.Language.IfStatementAst] -and $a.Clauses[0].Item1.Extent.Text -eq '-not $isAdmin'},$true)
& ([scriptblock]::Create($elevation.Clauses[0].Item2.Extent.Text.TrimStart('{').TrimEnd('}').Replace('$PSCommandPath','$entry')))
$decoded=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String(($script:captured -split '-EncodedCommand ')[1]));$r=& ([scriptblock]::Create($decoded))
Assert ($r.Apply -and $r.Quiet) 'real UAC command preserves explicit apply and noninteractive'
$path=$entry;$dispatch=$ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.IfStatementAst]}|Select-Object -Last 1
$r=& ([scriptblock]::Create($dispatch.Extent.Text))
Assert ($r.Apply -and $r.Quiet) 'real direct dispatch preserves Start flags'
$VerifyOnly=$true;$r=& ([scriptblock]::Create($dispatch.Extent.Text))
Assert ($r.Verify -and -not $r.Apply) 'verification dispatch never forwards policy installation'
$start=Parse 'core/start_windows.ps1';$request=[pscustomobject]@{DriverPackagePath='';ConfirmedBoard='';ConfirmationComputer=''}
$call=$start.FindAll({param($a) $a -is [Management.Automation.Language.CommandAst] -and $a.Extent.Text -like '*-DriverPackagePath $request.DriverPackagePath*'},$true)|Select-Object -Last 1
$fake=Join-Path $fixture 'configure.ps1';[IO.File]::WriteAllText($fake,'param($DriverPackagePath,$ConfirmedBoard,$ConfirmationComputer,[switch]$NonInteractive);$NonInteractive.IsPresent');$entry='configure.ps1'
$r=& ([scriptblock]::Create($call.Extent.Text.Replace('$PSScriptRoot','$fixture')))
Assert $r 'Windows entry forwards noninteractive to late policy gate'
. (Join-Path $repo 'core/paths.ps1')
foreach($name in @('start_pins_policy_library.ps1','start_pins_asset_library.ps1')){Assert (Test-Path -LiteralPath (Resolve-NucPath $name)) ('runtime dependency resolves '+$name)}
$pre=[IO.File]::ReadAllText((Join-Path $repo 'core/test_setup_prerequisites.ps1'))
Assert ($pre.Contains('Assert-StartPinsAssetSource')) 'offline preflight checks actual Start asset source without client native API'
