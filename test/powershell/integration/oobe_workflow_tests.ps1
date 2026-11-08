#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$workflow=[IO.File]::ReadAllText((Join-Path $root '.github/workflows/windows_tests.yml'))
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++}
$rollup=[regex]::Match($workflow,'(?ms)^  ci-rollup:\r?\n(?<body>.*?)^  release:').Groups['body'].Value
$scriptText=([regex]::Match($rollup,'(?ms)        run: \|\r?\n(?<body>.*)$').Groups['body'].Value -replace '(?m)^          ','').Trim()
$env:TEST_RESULT='success';$env:REQUIREMENTS_RESULT='success';$env:DOCKER_RESULT='success';$env:OOBE_PAYLOAD_RESULT='failure'
$rejected=$false;try{& ([scriptblock]::Create($scriptText))}catch{$rejected=$true}
Assert $rejected 'actual ci-rollup rejects failed OOBE package content inspection'
$env:OOBE_PAYLOAD_RESULT='success'
& ([scriptblock]::Create($scriptText))
Assert $true 'actual ci-rollup accepts all required jobs succeeding'
$job=[regex]::Match($workflow,'(?ms)^  oobe_payload_inspection:\r?\n(?<body>.*?)(?=^  [a-z][a-z_-]+:)').Groups['body'].Value
Assert ($job -match 'runs-on: windows-2022' -and $job -notmatch '(?m)^    needs:') 'payload inspection runs independently on Windows'
Assert ($job.Contains('verify_oobe_payload.ps1') -and $job.Contains('payload_baseline.json') -and $job.Contains('if: always()') -and $job.Contains('retention-days: 7')) 'CI invokes real reader with reviewed baseline and preserves failure evidence seven days'
Assert ($rollup.Contains('oobe_payload_inspection') -and $rollup.Contains('needs.oobe_payload_inspection.result')) 'rollup dependency and result refer to real payload job'
Write-Host ('ALL PASS: '+$script:count+' workflow contract assertions')
