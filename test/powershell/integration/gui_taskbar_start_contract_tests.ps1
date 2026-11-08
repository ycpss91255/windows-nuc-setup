#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$mapping=Get-Content -LiteralPath (Join-Path $root 'core/paths.json') -Raw|ConvertFrom-Json
foreach($case in @(@{Role='Taskbar';Folder='taskbar';Name='apply_taskbar_settings.ps1'},@{Role='Start';Folder='start_menu';Name='apply_start_menu_settings.ps1'})){
 $path=Join-Path $root ('modules/'+$case.Folder+'/'+$case.Name);$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
 $calls=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Invoke-SetupGuiRole'},$true))
 Assert ($errors.Count -eq 0 -and $ast.ScriptRequirements.IsElevationRequired -and $calls.Count -eq 1 -and $calls[0].Extent.Text.Contains('-Role '+$case.Role) -and $calls[0].Extent.Text.Contains('-VerifyOnly:$VerifyOnly') -and $calls[0].Extent.Text.Contains('-Worker:$Worker')) ('public '+$case.Role+' preserves standalone administrator contract and uses fixed private controller')
 Assert ([IO.File]::ReadAllText($path) -notmatch 'Copy-Item|New-ScheduledTask|NUC8-Setup|Set-Content') ('public '+$case.Role+' removes world-writable code and result authority')
}
foreach($name in @('taskbar_settings_library.ps1','taskbar_stage_library.ps1','start_menu_settings_library.ps1')){
 Assert ($mapping.$name -and (Test-Path -LiteralPath (Join-Path $root $mapping.$name)) -and [IO.File]::ReadAllText((Join-Path $root 'core/test_setup_prerequisites.ps1')).Contains("'"+$name+"'")) ('portable preflight requires true original source '+$name)
}
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'modules/taskbar/finalize_taskbar.ps1'),[ref]$tokens,[ref]$errors)
$call=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Invoke-SetupTaskbarFinalizePending'},$true))
Assert ($call.Count -eq 1 -and $ast.ScriptRequirements.IsElevationRequired) 'standalone finalizer only invokes fixed protected current-user pending run'
$tokens=$null;$errors=$null;$aggregate=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'core/verification_library.ps1'),[ref]$tokens,[ref]$errors)
foreach($role in @('Taskbar','Start')){
 $fresh=@($aggregate.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Invoke-SetupGuiFreshVerification' -and $n.Extent.Text.Contains('-Role '+$role)},$true))
 Assert ($fresh.Count -eq 1) ('core '+$role+' consumes current private result and native readback instead of legacy output')
}
Assert ([IO.File]::ReadAllText((Join-Path $root 'core/verification_library.ps1')) -notmatch 'NUC8-Setup\\TaskbarLayout.xml') 'Taskbar acceptance never trusts old public XML authority'