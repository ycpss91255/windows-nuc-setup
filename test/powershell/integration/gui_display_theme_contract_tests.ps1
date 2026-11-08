#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$mapping=Get-Content -LiteralPath (Join-Path $root 'core/paths.json') -Raw|ConvertFrom-Json
foreach($role in @('Display','Theme')){
 $lower=$role.ToLowerInvariant();$path=Join-Path $root ('modules/'+$lower+'/apply_'+$lower+'_settings.ps1')
 $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
 Assert ($errors.Count -eq 0 -and $ast.ScriptRequirements.IsElevationRequired -and (($ast.ParamBlock.Parameters.Name.VariablePath.UserPath|Sort-Object) -join ',') -ceq 'VerificationRunId,VerifyOnly,Worker') ($role+' preserves original public PowerShell5 administrator and parameter contract')
 $calls=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Invoke-SetupGuiRole'},$true))
 Assert ($calls.Count -eq 1 -and $calls[0].Extent.Text.Contains('-Role '+$role) -and $calls[0].Extent.Text.Contains('-Worker:$Worker') -and $calls[0].Extent.Text.Contains('-VerifyOnly:$VerifyOnly') -and $calls[0].Extent.Text.Contains('-VerificationRunId $VerificationRunId')) ($role+' routes all public modes and requested fresh ID through its fixed private controller')
 Assert ([IO.File]::ReadAllText($path) -notmatch 'Copy-Item|New-ScheduledTask|NUC8-Setup|Set-Content') ($role+' public entry cannot trust or publish old world-writable worker results')
 $name=$lower+'_settings_library.ps1'
 Assert ($mapping.$name -ceq ('modules/'+$lower+'/'+$name) -and [IO.File]::ReadAllText((Join-Path $root 'core/test_setup_prerequisites.ps1')).Contains("'"+$name+"'")) ($role+' leaf is mapped and required in portable package preflight')
}
$tokens=$null;$errors=$null;$aggregate=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'core/verification_library.ps1'),[ref]$tokens,[ref]$errors)
foreach($role in @('Display','Theme')){
 $fresh=@($aggregate.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Invoke-SetupGuiFreshVerification' -and $n.Extent.Text.Contains('-Role '+$role)},$true))
 Assert ($fresh.Count -eq 1) ('core '+$role+' acceptance consumes current protected direct result')
 $legacy=@($aggregate.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Invoke-FreshVerification' -and $n.Extent.Text.Contains('apply_'+$role.ToLowerInvariant()+'_settings.ps1')},$true))
 Assert ($legacy.Count -eq 0) ('core '+$role+' acceptance never treats public legacy JSON as fresh authority')
}
Assert ([IO.File]::ReadAllText((Join-Path $root 'core/verify_only.ps1')).Contains("Resolve-NucPath 'gui_stage_library.ps1'")) 'formal verifier loads its packaged fixed GUI adapter before aggregation'
