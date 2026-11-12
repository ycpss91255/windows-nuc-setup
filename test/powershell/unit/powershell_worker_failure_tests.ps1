#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$library=Join-Path $root 'script/test/powershell_worker_diagnostics.ps1'
Assert (Test-Path -LiteralPath $library -PathType Leaf) '提供不公開原始私有log的限型別worker失敗診斷'
. $library
$temp=Join-Path $env:TEMP ('worker_failure_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
$source=Join-Path $temp 'source';[void][IO.Directory]::CreateDirectory($source)
$stdout=Join-Path $temp 'stdout.private.log';$stderr=Join-Path $temp 'stderr.private.log';$secret='PRIVATE-CREDENTIAL-SENTINEL'
[IO.File]::WriteAllText($stdout,('@@ASSERT@@{"Name":"'+$secret+'","Passed":true}'+"`n"+'@@ASSERT@@{"Name":"'+$secret+'","Passed":false}'+"`n"+'@@ASSERT@@not-json'),[Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText($stderr,("At $source\core\example.ps1:42 char:3`nAt C:\Users\private\secret.ps1:9 char:2`nCategoryInfo : ignored [], RuntimeException`n"+$secret),[Text.UTF8Encoding]::new($false))
$d=Get-PowerShellWorkerFailureDiagnostic -SourceRoot $source -TestFile 'test/powershell/unit/fake_tests.ps1' -WorkerIndex 3 -Engine powershell -NativeExitCode 1 -StandardOutputPath $stdout -StandardErrorPath $stderr -AllowedFiles @('core/example.ps1')
Assert ($d.WorkerIndex -eq 3 -and $d.NativeExitCode -eq 1 -and $d.Engine -ceq 'powershell' -and $d.TestFile -ceq 'test/powershell/unit/fake_tests.ps1') '診斷保留已知case與原生失敗資訊，不改退出碼'
Assert ($d.CompletedAssertions -eq 2 -and @($d.FailedAssertionIndices).Count -eq 1 -and $d.FailedAssertionIndices[0] -eq 2) '只輸出失敗斷言順序，不公開斷言Name或執行內容'
Assert (@($d.Locations).Count -eq 1 -and $d.Locations[0].File -ceq 'core/example.ps1' -and $d.Locations[0].Line -eq 42) '只保留來源樹內相對檔名與行號'
Assert (@($d.ExceptionTypes) -contains 'RuntimeException') '只保留已知例外型別，不輸出訊息'
$json=$d|ConvertTo-Json -Depth 6 -Compress
Assert (-not $json.Contains($secret) -and -not $json.Contains($source) -and -not $json.Contains('C:\Users') -and -not $json.Contains('secret.ps1')) '私人值、絕對路徑與外部檔名都不能進診斷輸出'
$empty=Get-PowerShellWorkerFailureDiagnostic -SourceRoot $source -TestFile '../private.ps1' -WorkerIndex 0 -Engine pwsh -NativeExitCode -1 -StandardOutputPath (Join-Path $temp 'missing') -StandardErrorPath (Join-Path $temp 'missing2')
Assert ($empty.TestFile -ceq 'unavailable.ps1' -and $empty.CompletedAssertions -eq 0 -and @($empty.Locations).Count -eq 0 -and $empty.NativeExitCode -eq -1) '失敗產物缺失或不合法case只回限型別摘要、不掩蓋原失敗'
$many=@(1..505|ForEach-Object {'@@ASSERT@@{"Name":"'+$secret+'","Passed":true}'})+@('@@ASSERT@@{"Name":"'+$secret+'","Passed":false}')
[IO.File]::WriteAllLines($stdout,[string[]]$many,[Text.UTF8Encoding]::new($false))
$all=Get-PowerShellWorkerFailureDiagnostic -SourceRoot $source -TestFile 'test/powershell/unit/fake_tests.ps1' -WorkerIndex 0 -Engine powershell -NativeExitCode 1 -StandardOutputPath $stdout -StandardErrorPath $stderr
Assert ($all.CompletedAssertions -eq 506 -and $all.FailedAssertionIndices[0] -eq 506) '逐行讀取保留真正全程斷言ordinal，不把tail索引冒稱全程位置'
Assert (@($all.Locations).Count -eq 0) '來源內但未列入canonical的任意檔名不公開'
$rooted=Get-PowerShellWorkerFailureDiagnostic -SourceRoot $source -TestFile '/Users/private/secret.ps1' -WorkerIndex 0 -Engine powershell -NativeExitCode 1 -StandardOutputPath (Join-Path $temp 'missing') -StandardErrorPath (Join-Path $temp 'missing2')
Assert ($rooted.TestFile -ceq 'unavailable.ps1') 'Unix形式絕對路徑亦不得冒充相對case'
[IO.File]::WriteAllText($stdout,'@@ASSERT@@{"Name":"IOException PRIVATE-CREDENTIAL-SENTINEL","Passed":false}',[Text.UTF8Encoding]::new($false))
$named=Get-PowerShellWorkerFailureDiagnostic -SourceRoot $source -TestFile 'case.ps1' -WorkerIndex 0 -Engine powershell -NativeExitCode 1 -StandardOutputPath $stdout -StandardErrorPath (Join-Path $temp 'missing2')
Assert (@($named.ExceptionTypes).Count -eq 0) '斷言Name中的例外字詞不能冒充實際例外型別'
$global:LASTEXITCODE=0
[IO.File]::WriteAllLines($stdout,[string[]]@('@@SAFE_FIXTURE_DIAG@@fixture_export:go_fixture_failed','@@SAFE_FIXTURE_DIAG@@fixture_export:PRIVATE-CREDENTIAL-SENTINEL','@@SAFE_FIXTURE_DIAG@@C:\Users\private\secret'),[Text.UTF8Encoding]::new($false))
$safe=Get-PowerShellWorkerFailureDiagnostic -SourceRoot $source -TestFile 'test/powershell/integration/report_bundle_publication_tests.ps1' -WorkerIndex 1 -Engine powershell -NativeExitCode 1 -StandardOutputPath $stdout -StandardErrorPath (Join-Path $temp 'missing2')
Assert ($safe.FixtureStage -ceq 'fixture_export' -and $safe.FixtureReason -ceq 'go_fixture_failed') '固定白名單保留合成工件失敗階段'
$safeJson=$safe|ConvertTo-Json -Depth 6 -Compress
Assert (-not $safeJson.Contains($secret) -and -not $safeJson.Contains('C:\Users')) '未知原因與私有路徑不得進診斷'
[IO.File]::WriteAllText($stdout,'@@SAFE_FIXTURE_DIAG@@fixture_export:PRIVATE-CREDENTIAL-SENTINEL',[Text.UTF8Encoding]::new($false))
$unknown=Get-PowerShellWorkerFailureDiagnostic -SourceRoot $source -TestFile 'test/powershell/integration/report_bundle_publication_tests.ps1' -WorkerIndex 1 -Engine powershell -NativeExitCode 1 -StandardOutputPath $stdout -StandardErrorPath (Join-Path $temp 'missing2')
Assert (-not $unknown.FixtureStage -and -not $unknown.FixtureReason) '未知診斷碼不得公開'
[IO.File]::WriteAllText($stdout,'@@SAFE_FIXTURE_DIAG@@fixture_export:go_fixture_failed',[Text.UTF8Encoding]::new($false))
$wrongSuite=Get-PowerShellWorkerFailureDiagnostic -SourceRoot $source -TestFile 'test/powershell/unit/unrelated_tests.ps1' -WorkerIndex 1 -Engine powershell -NativeExitCode 1 -StandardOutputPath $stdout -StandardErrorPath (Join-Path $temp 'missing2')
Assert (-not $wrongSuite.FixtureStage -and -not $wrongSuite.FixtureReason) '非工件測試不得冒充固定診斷'
