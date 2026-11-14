#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/report/repo_coverage.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$json='{"SchemaVersion":2,"Metric":"runtime-powershell-csharp-executable-lines-v2","Scope":"core-modules-powershell-and-modules-native-csharp","Commit":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","RunUrl":"https://github.com/example/repo/actions/runs/1","MeasuredAt":"2026-01-01T00:00:00Z","SourceState":"Clean","InventorySHA256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","NormalizedSHA256":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","Result":{"SchemaVersion":1,"Metric":"complete-executable-lines-v1","Complete":true,"Covered":4,"Executable":5,"Percent":80,"Missing":[],"Blockers":[],"Languages":{"powershell":{"Covered":4,"Executable":5}}}}'
$coverage=$json|ConvertFrom-Json
Assert-RepoCoverage -Coverage $coverage
Assert ((Get-RepoCoverageScopeLabel $coverage) -eq 'PowerShell/C# runtime') 'Runtime scope is explicit'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('windows_setup_runtime_schema_'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($temp)
[IO.File]::WriteAllText((Join-Path $temp 'repo_coverage.json'),($coverage|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
$tool=Join-Path $temp 'verify.cmd';$capture=Join-Path $temp 'arguments.txt'
[IO.File]::WriteAllText($tool,"@echo off`r`necho %* > `"%RUNTIME_SCHEMA_ARGS%`"`r`nexit /b 0`r`n",[Text.Encoding]::ASCII)
$previous=$env:RUNTIME_SCHEMA_ARGS;$env:RUNTIME_SCHEMA_ARGS=$capture
try {
 $report=[pscustomobject]@{SchemaVersion=2;Commit=$coverage.Commit;RunUrl=$coverage.RunUrl;SourceState='Clean';RepoCoverage=$coverage}
 Assert-RepoCoverageArtifacts -Report $report -Directory $temp -CoverageToolPath $tool -RequireComplete
 Assert ([IO.File]::ReadAllText($capture).Contains('--runtime')) 'Runtime verifier mode is required'
} finally {$env:RUNTIME_SCHEMA_ARGS=$previous}
$coverage.Scope='all-owned' 
$rejected=$false;try{Assert-RepoCoverage -Coverage $coverage}catch{$rejected=$true}
Assert $rejected 'Altered scope rejected'
