#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../../modules/start_menu/start_pins_policy_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
Assert ([bool](Get-Command Invoke-StartPinsConfiguration -ErrorAction SilentlyContinue)) 'real module orchestration is named and safely testable'
$script:route='LegacyPackage';$script:writes=0;$script:legacy=@();$script:exported=0
function Get-StartPinsRoute {param($Build,$Revision,$AdmxText);$script:route}
function Get-ItemProperty {param($LiteralPath,$ErrorAction);[pscustomobject]@{CurrentBuildNumber='22621';UBR=1}}
function Invoke-StartPinsLegacyPolicy {param($AssetRoot,[switch]$ApplyPolicy,[switch]$NonInteractive,$Confirm);$script:legacy+=@{Apply=[bool]$ApplyPolicy;NoPrompt=[bool]$NonInteractive};[pscustomobject]@{Status='LegacyPendingApply';PolicyInstalled=$false}}
function Get-StartPinsExportState {param($ExportPath,$PolicyState);$script:exported++;@{Success=$false;Status=$PolicyState.Status;PinCount=3}}
function Set-Content {param($LiteralPath,$Value,$Encoding,$ErrorAction);$script:writes++}
function New-Item {param($Path,[switch]$Force);$script:writes++}
function New-ItemProperty {param($Path,$Name,$PropertyType,$Value,[switch]$Force);$script:writes++}
$r=Invoke-StartPinsConfiguration -AssetRoot $env:TEMP -OutputRoot $env:TEMP -AdmxPath (Join-Path $env:TEMP 'no_such_start_admx_fixture')
Assert ($r.Status -eq 'LegacyPendingApply' -and $script:writes -eq 0 -and -not $script:legacy[-1].Apply) 'old Windows avoids unavailable GPO and queues policy without apply'
$r=Invoke-StartPinsConfiguration -AssetRoot $env:TEMP -OutputRoot $env:TEMP -VerifyOnly -ApplyPolicy
Assert (-not $script:legacy[-1].Apply -and $script:writes -eq 0) 'verification cannot install even with ApplyPolicy switch'
$r=Invoke-StartPinsConfiguration -AssetRoot $env:TEMP -OutputRoot $env:TEMP -ApplyPolicy -NonInteractive
Assert ($script:legacy[-1].Apply -and $script:legacy[-1].NoPrompt) 'explicit late mode forwards noninteractive protection'
$script:route='Gpo'
$r=Invoke-StartPinsConfiguration -AssetRoot $env:TEMP -OutputRoot $env:TEMP
Assert ($script:writes -ge 3 -and $script:legacy.Count -eq 3) 'supported GPO does not install device provisioning policy'
$before=$script:writes;$r=Invoke-StartPinsConfiguration -AssetRoot $env:TEMP -OutputRoot $env:TEMP -VerifyOnly
Assert ($script:writes -eq $before -and $script:exported -eq 5) 'GPO verifier only exports actual pins'
# Exercise the actual product call, not a mirrored invocation.
$entry=Get-Content (Join-Path $PSScriptRoot '../../../modules/start_menu/apply_start_menu_settings.ps1') -Raw
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($entry,[ref]$t,[ref]$e)
$call=$ast.Find({param($a)$a -is [Management.Automation.Language.CommandAst] -and $a.GetCommandName() -eq 'Invoke-StartPinsConfiguration'},$true)
Assert ([bool]$call) 'actual module calls shared version-aware configuration'
& {
 $assetRoot='C:\fixture assets';$root='C:\fixture output';$VerifyOnly=$true;$ApplyPolicy=$true;$NonInteractive=$true
 function Invoke-StartPinsConfiguration {param($AssetRoot,$OutputRoot,[switch]$VerifyOnly,[switch]$ApplyPolicy,[switch]$NonInteractive);Assert ($AssetRoot -eq 'C:\fixture assets' -and $OutputRoot -eq 'C:\fixture output' -and $VerifyOnly -and $ApplyPolicy -and $NonInteractive) 'actual module forwards context and all safety switches'}
 . ([scriptblock]::Create($call.Extent.Text))
}
