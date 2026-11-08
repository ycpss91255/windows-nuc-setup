#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/start_menu/start_pins_policy_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
Assert ([bool](Get-Command Get-StartPinsExportState -ErrorAction SilentlyContinue)) 'actual export determines confirmed or sign-in pending state'
$fixture=Join-Path $env:TEMP ('start_export_'+[guid]::NewGuid().ToString('N')+'.json');$script:json='{"pinnedList":[{"desktopAppId":"MSEdge"}]}'
function Export-StartLayout {param($Path,$ErrorAction);[IO.File]::WriteAllText($Path,$script:json)}
$r=Get-StartPinsExportState $fixture ([pscustomobject]@{Status='PendingSignIn';PolicyInstalled=$true})
Assert (-not $r.Success -and $r.Status -eq 'PendingSignIn' -and $r.PinCount -eq 1) 'native policy installation alone cannot imply pin removal'
$script:json='{"pinnedList":[]}'
$r=Get-StartPinsExportState $fixture ([pscustomobject]@{Status='PendingSignIn';PolicyInstalled=$true})
Assert ($r.Success -and $r.Status -eq 'Confirmed') 'real empty export confirms applied policy'
$r=Get-StartPinsExportState $fixture ([pscustomobject]@{Status='LegacyPendingApply';PolicyInstalled=$false})
Assert (-not $r.Success -and $r.Status -eq 'LegacyPendingApply') 'empty layout cannot conceal unapplied policy'
$script:json='{}';$failed=$false;try{Get-StartPinsExportState $fixture ([pscustomobject]@{Status='PendingSignIn';PolicyInstalled=$true})}catch{$failed=$true}
Assert $failed 'missing pinnedList is not interpreted as empty pins'
$entry=Get-Content (Join-Path $root 'modules/start_menu/apply_start_menu_settings.ps1') -Raw
$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($entry,[ref]$t,[ref]$e)
Assert (@($ast.ParamBlock.Parameters.Name.VariablePath.UserPath) -contains 'ApplyPolicy') 'module has explicit late application switch'
Assert (@($ast.ParamBlock.Parameters.Name.VariablePath.UserPath) -contains 'NonInteractive') 'module supports deterministic no-prompt mode'
