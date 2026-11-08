#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
$source=[IO.File]::ReadAllText((Join-Path $root 'core/run_module.ps1'))
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
$elevation=$ast.Find({param($a) $a -is [Management.Automation.Language.IfStatementAst] -and $a.Clauses[0].Item1.Extent.Text -eq '-not $isAdmin'},$true)
if(-not $elevation){throw 'Missing actual elevation branch'}
$fixture=Join-Path $env:TEMP ('module_identity_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $fixture|Out-Null
$entry=Join-Path $fixture "module ' 中文.ps1"
[IO.File]::WriteAllText($entry,'param($Module,$ExpectedUserSID,[switch]$VerifyOnly,[switch]$SyncOnly,$Mode,$DriverPackagePath);[pscustomobject]@{Module=$Module;SID=$ExpectedUserSID;Verify=$VerifyOnly.IsPresent;Sync=$SyncOnly.IsPresent;Mode=$Mode;Driver=$DriverPackagePath}',[Text.UTF8Encoding]::new($true))
function Start-Process {param($FilePath,$Verb,$ArgumentList);$script:captured=$ArgumentList}
$PSCommandPath=$entry;$sid='S-1-5-21-111-222-333-1001';$currentSID=$sid
$Module='Apply-HostsSync';$VerifyOnly=$true;$SyncOnly=$false;$Mode='SSH';$DriverPackagePath=''
& ([scriptblock]::Create($elevation.Clauses[0].Item2.Extent.Text.TrimStart('{').TrimEnd('}').Replace('$PSCommandPath','$entry')))
$decoded=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String(($script:captured -split '-EncodedCommand ')[1]))
$result=& ([scriptblock]::Create($decoded))
Assert ($result.SID -eq $sid -and $result.Module -eq $Module -and $result.Verify -and $result.Mode -eq 'SSH') 'standalone elevation carries original user SID and requested verification flags'
$Module='Install-Drivers';$VerifyOnly=$false;$DriverPackagePath=Join-Path $fixture "drivers ' 中文"
& ([scriptblock]::Create($elevation.Clauses[0].Item2.Extent.Text.TrimStart('{').TrimEnd('}').Replace('$PSCommandPath','$entry')))
$decoded=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String(($script:captured -split '-EncodedCommand ')[1]))
$result=& ([scriptblock]::Create($decoded))
Assert ($result.SID -eq $sid -and $result.Driver -eq $DriverPackagePath) 'standalone elevation preserves quoted dynamic driver path with original identity'
$guard=$ast.Find({param($a) $a -is [Management.Automation.Language.IfStatementAst] -and $a.Clauses[0].Item1.Extent.Text -match '^\$ExpectedUserSID -and'},$true)
Assert ($null -ne $guard -and $ast.ParamBlock.Parameters.Name.VariablePath.UserPath -contains 'ExpectedUserSID') 'standalone entry exposes and executes the identity guard'
$ExpectedUserSID='original';$sid='different';$currentSID=$sid;$called=$false;$refused=$false
try { . ([scriptblock]::Create($guard.Extent.Text));$called=$true } catch {$refused=$true}
Assert ($refused -and -not $called) 'different elevation account is rejected before module execution'
$ExpectedUserSID=$sid;$called=$false
. ([scriptblock]::Create($guard.Extent.Text));$called=$true
Assert $called 'same account remains usable without requiring a local Explorer session'