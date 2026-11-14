#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/report/repo_coverage.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$json='{"SchemaVersion":2,"Metric":"runtime-powershell-csharp-executable-lines-v2","Scope":"core-modules-powershell-and-modules-native-csharp","Commit":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","RunUrl":"https://github.com/example/repo/actions/runs/1","MeasuredAt":"2026-01-01T00:00:00Z","SourceState":"Clean","InventorySHA256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","NormalizedSHA256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","Result":{"SchemaVersion":1,"Metric":"complete-executable-lines-v1","Complete":true,"Covered":4,"Executable":5,"Percent":80,"Missing":[],"Blockers":[],"Languages":{"powershell":{"Covered":4,"Executable":5}}}}'
$coverage=$json|ConvertFrom-Json
Assert-RepoCoverage -Coverage $coverage
Assert ((Get-RepoCoverageScopeLabel $coverage) -eq 'PowerShell/C# runtime') 'Runtime scope is explicit'
$coverage.Scope='all-owned'
$rejected=$false;try{Assert-RepoCoverage -Coverage $coverage}catch{$rejected=$true}
Assert $rejected 'Altered scope rejected'
