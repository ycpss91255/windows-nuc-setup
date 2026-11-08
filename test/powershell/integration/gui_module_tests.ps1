#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name};$script:count++}
. (Join-Path $root 'core/gui_stage_library.ps1')
$entry=Join-Path $root 'modules/explorer/apply_explorer_settings.ps1'
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($entry,[ref]$tokens,[ref]$errors)
Assert ($errors.Count -eq 0 -and $ast.ScriptRequirements.IsElevationRequired) 'Explorer public entry preserves PowerShell5 parsing and administrator requirement'
$parameters=@($ast.ParamBlock.Parameters|ForEach-Object {$_.Name.VariablePath.UserPath}|Sort-Object)
Assert (($parameters -join ',') -ceq 'VerifyOnly,Worker') 'Explorer public Worker and VerifyOnly API remains unchanged'
$calls=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Invoke-SetupGuiRole'},$true))
Assert ($calls.Count -eq 1 -and $calls[0].Extent.Text -match '-Role Explorer' -and $calls[0].Extent.Text -match '-Worker:\$Worker' -and $calls[0].Extent.Text -match '-VerifyOnly:\$VerifyOnly') 'Explorer public entry routes every mode to protected role controller'
Assert ([IO.File]::ReadAllText($entry) -notmatch 'Copy-Item|New-ScheduledTask|NUC8-Setup') 'Explorer public entry cannot retain old public-code worker or legacy-result path'
$mapping=[IO.File]::ReadAllText((Join-Path $root 'core/paths.json'))|ConvertFrom-Json
foreach($item in @(@{Name='gui_stage_library.ps1';Path='core/gui_stage_library.ps1'},@{Name='gui_worker.ps1';Path='core/gui_worker.ps1'},@{Name='explorer_settings_library.ps1';Path='modules/explorer/explorer_settings_library.ps1'})){
 Assert ($mapping.($item.Name) -ceq $item.Path -and (Test-Path -LiteralPath (Join-Path $root $item.Path))) ('packaged GUI dependency has explicit relocatable mapping: '+$item.Name)
 Assert ([IO.File]::ReadAllText((Join-Path $root 'core/test_setup_prerequisites.ps1')).Contains("'"+$item.Name+"'")) ('package preflight requires '+$item.Name)
}
foreach($name in @(Get-SetupGuiStageFiles Explorer)){Assert (Test-Path -LiteralPath (Join-Path $root $name) -PathType Leaf) ('fixed worker manifest is self-contained in source: '+$name)}
$worker=Join-Path $root 'core/gui_worker.ps1';$workerAst=[Management.Automation.Language.Parser]::ParseFile($worker,[ref]$tokens,[ref]$errors)
Assert ($errors.Count -eq 0 -and $workerAst.ScriptRequirements.IsElevationRequired -and (($workerAst.ParamBlock.Parameters.Name.VariablePath.UserPath|Sort-Object) -join ',') -ceq 'Role,RunId') 'fixed worker accepts only bounded role/run ID and keeps elevation requirement'
Write-Host ('ALL PASS: '+$script:count+' GUI source/contract integration assertions; no public entry executed and no host changes')