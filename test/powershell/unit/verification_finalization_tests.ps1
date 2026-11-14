#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
. (Join-Path $root 'core/hardware.ps1')
. (Join-Path $root 'core/verification_library.ps1')
Assert ([bool](Get-Command Complete-SetupVerificationResult -CommandType Function -ErrorAction SilentlyContinue)) 'named verification finalization exists'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'core/verification_library.ps1'),[ref]$tokens,[ref]$errors)
$entry=$ast.Find({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-SetupVerification'},$true)
$calls=@($entry.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Complete-SetupVerificationResult'},$true))
Assert ($errors.Count -eq 0 -and $calls.Count -eq 1) 'actual verification entry calls finalizer once'
$fixture=Join-Path $env:TEMP ('verify_finalization_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
function Resolve-NucPath {param([string]$Name) if($Name -cne 'Verification-Result.json'){throw 'unexpected report path'};Join-Path $fixture $Name}
function Get-ItemProperty {throw 'unexpected registry access'}
function Set-ItemProperty {throw 'unexpected registry access'}
function Get-Service {throw 'unexpected service access'}
function Set-Service {throw 'unexpected service access'}
function Start-Service {throw 'unexpected service access'}
function Get-CimInstance {throw 'unexpected system query'}
function Get-NetFirewallRule {throw 'unexpected firewall access'}
function Set-NetFirewallRule {throw 'unexpected firewall access'}
function New-NetFirewallRule {throw 'unexpected firewall access'}
function Get-AppxPackage {throw 'unexpected Appx access'}
function Get-AppxProvisionedPackage {throw 'unexpected Appx access'}
function Start-Process {throw 'unexpected process start'}
$id=[guid]::NewGuid().ToString();$hardware=[pscustomobject]@{Name='Fixture'};$report=Join-Path $fixture 'Verification-Result.json'
foreach($mode in @('success','failure','skipped','empty')){
 $checks=New-Object Collections.Generic.List[object]
 if($mode -eq 'success'){$checks.Add([pscustomobject]@{Name='ok';Status='Passed';Passed=$true})}
 if($mode -eq 'failure'){$checks.Add([pscustomobject]@{Name='failed';Status='Failed';Passed=$false})}
 if($mode -eq 'skipped'){$checks.Add([pscustomobject]@{Name='skipped';Status='Skipped';Passed=$null})}
 if(Test-Path -LiteralPath $report){[IO.File]::Delete($report)}
 $message='';try{Complete-SetupVerificationResult -Checks $checks -Hardware $hardware -VerificationRunId $id}catch{$message=$_.Exception.Message}
 Assert (Test-Path -LiteralPath $report -PathType Leaf) ('result exists before return or throw: '+$mode)
 $actual=Get-Content -LiteralPath $report -Raw|ConvertFrom-Json
 Assert ($actual.VerificationRunId -ceq $id -and $actual.UserSID -ceq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value -and $actual.Computer -ceq $env:COMPUTERNAME -and $actual.HardwareProfile.Name -ceq 'Fixture' -and @($actual.Checks).Count -eq $checks.Count -and $actual.SkippedCount -eq [int]($mode -eq 'skipped')) ('result preserves identity, checks and skipped count: '+$mode)
 Assert ($actual.Passed -eq ($mode -ne 'failure') -and (($message -ceq '驗證未全部通過；已寫入 Verification-Result.json。') -eq ($mode -eq 'failure'))) ('result preserves pass and exception contract: '+$mode)
}
