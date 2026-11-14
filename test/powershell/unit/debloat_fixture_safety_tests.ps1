#Requires -Version 5.1
$ErrorActionPreference='Stop'
$path=Join-Path $PSScriptRoot 'debloat_log_location_tests.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'fixture 無法解析'}
$unsafe=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $node.Expression.Extent.Text -eq '[scriptblock]' -and $node.Member.Value -eq 'Create'},$true))
if($unsafe.Count){throw 'fixture 不得動態執行擷取的上游程式文字'}
Write-Host '@@ASSERT@@{"Name":"fixture 不動態執行上游程式片段","Passed":true}'