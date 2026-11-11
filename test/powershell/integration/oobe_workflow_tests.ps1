#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$workflow=[IO.File]::ReadAllText((Join-Path $root '.github/workflows/windows_tests.yml'))
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++}
$rollup=[regex]::Match($workflow,'(?ms)^  ci-rollup:\r?\n(?<body>.*?)^  release:').Groups['body'].Value
$scriptText=([regex]::Match($rollup,'(?ms)        run: \|\r?\n(?<body>.*)$').Groups['body'].Value -replace '(?m)^          ','').Trim()
$env:TEST_RESULT='success';$env:REQUIREMENTS_RESULT='success';$env:DOCKER_RESULT='success';$env:POWERSHELL_COVERAGE_RESULT='success';$env:OOBE_PAYLOAD_RESULT='failure'
$rejected=$false;try{& ([scriptblock]::Create($scriptText))}catch{$rejected=$true}
Assert $rejected 'actual ci-rollup rejects failed OOBE package content inspection'
$env:OOBE_PAYLOAD_RESULT='success'
& ([scriptblock]::Create($scriptText))
Assert $true 'actual ci-rollup accepts all required jobs succeeding'
$env:POWERSHELL_COVERAGE_RESULT='failure'
$rejected=$false;try{& ([scriptblock]::Create($scriptText))}catch{$rejected=$true}
Assert $rejected 'actual ci-rollup rejects failed or incomplete PowerShell shard matrix'
$env:POWERSHELL_COVERAGE_RESULT='success'
$job=[regex]::Match($workflow,'(?ms)^  oobe_payload_inspection:\r?\n(?<body>.*?)(?=^  [a-z][a-z_-]+:)').Groups['body'].Value
Assert ($job -match 'runs-on: windows-2022' -and $job -notmatch '(?m)^    needs:') 'payload inspection runs independently on Windows'
Assert ($job.Contains('verify_oobe_payload.ps1') -and $job.Contains('payload_baseline.json') -and $job.Contains('if: always()') -and $job.Contains('retention-days: 7')) 'CI invokes real reader with reviewed baseline and preserves failure evidence seven days'
Assert ($job -match '(?s)name:.*?三檔來源與實際雜湊\r?\n\s+shell: powershell\r?\n\s+run: \|\r?\n\s+.*provisioning_source_tests\.ps1' -and $job -match '(?s)id: payload\r?\n\s+if: always\(\)') 'CI names real source verification accurately and preserves independent native WIM inspection'
Assert ($rollup.Contains('oobe_payload_inspection') -and $rollup.Contains('needs.oobe_payload_inspection.result')) 'rollup dependency and result refer to real payload job'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('oobe_workflow_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $fixture 'script/test') -Force|Out-Null
[IO.File]::WriteAllText((Join-Path $fixture 'script/test/verify_oobe_payload.ps1'),'param($PackagePath,$EvidenceDirectory,$BaselinePath); [IO.File]::WriteAllText((Join-Path $PWD "capture.json"),(@{EvidenceDirectory=$EvidenceDirectory;OutputBeforeRead=[IO.File]::ReadAllText($env:GITHUB_OUTPUT)}|ConvertTo-Json))')
$run=([regex]::Match($job.Substring($job.IndexOf('id: payload')),'(?ms)        run: \|\r?\n(?<body>.*?)(?=^      - name:)').Groups['body'].Value -replace '(?m)^          ','').Trim()
$oldRunner=$env:RUNNER_TEMP;$oldOutput=$env:GITHUB_OUTPUT
try{
 $env:RUNNER_TEMP=Join-Path $fixture 'different_runner_temp';$env:GITHUB_OUTPUT=Join-Path $fixture 'github_output'
 [IO.File]::WriteAllText($env:GITHUB_OUTPUT,'')
 Push-Location $fixture
 try{& ([scriptblock]::Create($run))}finally{Pop-Location}
 $capture=[IO.File]::ReadAllText((Join-Path $fixture 'capture.json'))|ConvertFrom-Json
 Assert ((Split-Path $capture.EvidenceDirectory -Parent).TrimEnd('\') -eq ([IO.Path]::GetTempPath()).TrimEnd('\')) 'real workflow selects native TEMP when RUNNER_TEMP differs'
 Assert ($capture.OutputBeforeRead.Contains('evidence='+$capture.EvidenceDirectory)) 'workflow publishes evidence output before invoking reader'
 Assert ($job.Contains('id: payload') -and $job.Contains('path: ${{ steps.payload.outputs.evidence }}')) 'artifact upload uses the exact reader output path'
}finally{$env:RUNNER_TEMP=$oldRunner;$env:GITHUB_OUTPUT=$oldOutput}
Write-Host ('ALL PASS: '+$script:count+' workflow contract assertions')
