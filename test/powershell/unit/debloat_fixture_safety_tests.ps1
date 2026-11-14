#Requires -Version 5.1
$ErrorActionPreference='Stop'
$path=Join-Path $PSScriptRoot 'debloat_log_location_tests.ps1'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'fixture 無法解析'}
$unsafe=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $node.Expression.Extent.Text -eq '[scriptblock]' -and $node.Member.Value -eq 'Create'},$true))
if($unsafe.Count){throw 'fixture 不得動態執行擷取的上游程式文字'}
Write-Host '@@ASSERT@@{"Name":"fixture 不動態執行上游程式片段","Passed":true}'
# Inspect the vendored script structurally; do not execute it or any extracted fragment.
$upstream=Join-Path $PSScriptRoot '../../../modules/debloat/win11debloat/Win11Debloat.ps1'
$tokens=$null;$errors=$null
$source=[Management.Automation.Language.Parser]::ParseFile([IO.Path]::GetFullPath($upstream),[ref]$tokens,[ref]$errors)
if($errors.Count){throw '上游來源無法解析'}
$ifs=@($source.FindAll({param($n) $n -is [Management.Automation.Language.IfStatementAst]},$true))
$logIf=@($ifs|Where-Object {$_.Clauses[0].Item1.Extent.Text -ceq '$LogPath -and (Test-Path $LogPath)'})
if($logIf.Count -ne 1){throw '上游 LogPath 目錄條件變更'}
$commands=@($logIf[0].Clauses[0].Item2.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst]},$true))
$join=@($commands|Where-Object {$_.GetCommandName() -ceq 'Join-Path' -and $_.CommandElements.Count -eq 3 -and $_.CommandElements[1].Extent.Text -ceq '$LogPath' -and $_.CommandElements[2].Value -ceq 'Win11Debloat.log'})
$transcript=@($commands|Where-Object {$_.GetCommandName() -ceq 'Start-Transcript' -and $_.CommandElements[1].ParameterName -ceq 'Path' -and $_.CommandElements[2].FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -ceq 'Join-Path'},$true).Count -eq 1})
if($join.Count -ne 1 -or $transcript.Count -ne 1){throw '上游 transcript 檔名或目錄契約變更'}
$dataIf=@($ifs|Where-Object {$_.Clauses[0].Item1.Extent.Text -ceq '[string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)'})
if($dataIf.Count -ne 1){throw '上游使用者資料 fallback 條件變更'}
$assign=@($dataIf[0].Clauses[0].Item2.FindAll({param($n) $n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -ceq '$script:UserDataPath' -and $n.Right.Extent.Text -ceq '$PSScriptRoot'},$true))
$other=@($dataIf[0].ElseClause.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -ceq 'Join-Path' -and $n.CommandElements.Count -eq 3 -and $n.CommandElements[1].Extent.Text -ceq '$env:LOCALAPPDATA' -and $n.CommandElements[2].Value -ceq 'Win11Debloat'},$true))
if($assign.Count -ne 1 -or $other.Count -ne 1){throw '上游使用者資料路徑契約變更'}
Write-Host '@@ASSERT@@{"Name":"靜態 AST 核對上游記錄與資料目錄契約","Passed":true}'