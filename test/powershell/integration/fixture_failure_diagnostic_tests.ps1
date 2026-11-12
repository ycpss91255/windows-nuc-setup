#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$fixture=Join-Path $env:TEMP ('fixture_diagnostic_worker_'+[guid]::NewGuid().ToString('N'))
foreach($directory in @('core','test/powershell/helpers','test/powershell/integration','test/powershell/coverage')){New-Item -ItemType Directory -Path (Join-Path $fixture $directory) -Force|Out-Null}
Copy-Item -LiteralPath (Join-Path $root 'test/powershell/helpers/report_bundle_fixture.ps1') -Destination (Join-Path $fixture 'test/powershell/helpers/report_bundle_fixture.ps1')
Copy-Item -LiteralPath (Join-Path $root 'test/powershell/coverage/safe_suite.ps1') -Destination (Join-Path $fixture 'test/powershell/coverage/safe_suite.ps1')
[IO.File]::WriteAllText((Join-Path $fixture 'core/minimal.ps1'),"function Test-Minimal { return 1 }`n",[Text.UTF8Encoding]::new($true))
$suite=@'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'test/powershell/helpers/report_bundle_fixture.ps1')
function go.exe {Write-Output 'PRIVATE-CREDENTIAL-SENTINEL C:\Users\private\secret';$global:LASTEXITCODE=1}
New-TestReportBundleFixture -RepositoryRoot $root -Destination (Join-Path $env:TEMP ('fixture_worker_child_'+[guid]::NewGuid().ToString('N')))
'@
[IO.File]::WriteAllText((Join-Path $fixture 'test/powershell/integration/report_bundle_publication_tests.ps1'),$suite,[Text.UTF8Encoding]::new($true))
$manifest=Join-Path $fixture 'manifest.json';$output=Join-Path $fixture 'output';$log=Join-Path $fixture 'collector.private.log'
$input=[ordered]@{SourceRoot=$fixture;Sources=@('core/minimal.ps1');Tests=@('test/powershell/integration/report_bundle_publication_tests.ps1');Wrapper='test/powershell/coverage/safe_suite.ps1'}
[IO.File]::WriteAllText($manifest,($input|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
$prior=$ErrorActionPreference
try{$ErrorActionPreference='Continue';& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'script/test/powershell_coverage.ps1') -ManifestPath $manifest -OutputDirectory $output > $log 2>&1;$failed=($LASTEXITCODE -ne 0)}finally{$ErrorActionPreference=$prior}
$text=[IO.File]::ReadAllText($log)
Assert $failed '真 Pester worker 中合成工件失敗仍使收集失敗'
Assert ($text.Contains('"FixtureStage":"fixture_export"') -and $text.Contains('"FixtureReason":"go_fixture_failed"')) '真 worker 的公開診斷包含固定階段與原因'
Assert (-not $text.Contains('PRIVATE-CREDENTIAL-SENTINEL') -and -not $text.Contains('C:\Users\private')) '真 worker 的公開診斷不含私密子程序輸出'
