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
$d=Get-PowerShellWorkerFailureDiagnostic -SourceRoot $source -TestFile 'test/powershell/unit/fake_tests.ps1' -WorkerIndex 3 -Engine powershell -NativeExitCode 1 -StandardOutputPath $stdout -StandardErrorPath $stderr
Assert ($d.WorkerIndex -eq 3 -and $d.NativeExitCode -eq 1 -and $d.Engine -ceq 'powershell' -and $d.TestFile -ceq 'test/powershell/unit/fake_tests.ps1') '診斷保留已知case與原生失敗資訊，不改退出碼'
Assert ($d.CompletedAssertions -eq 2 -and @($d.FailedAssertionIndices).Count -eq 1 -and $d.FailedAssertionIndices[0] -eq 2) '只輸出失敗斷言順序，不公開斷言Name或執行內容'
Assert (@($d.Locations).Count -eq 1 -and $d.Locations[0].File -ceq 'core/example.ps1' -and $d.Locations[0].Line -eq 42) '只保留來源樹內相對檔名與行號'
Assert (@($d.ExceptionTypes) -contains 'RuntimeException') '只保留已知例外型別，不輸出訊息'
$json=$d|ConvertTo-Json -Depth 6 -Compress
Assert (-not $json.Contains($secret) -and -not $json.Contains($source) -and -not $json.Contains('C:\Users') -and -not $json.Contains('secret.ps1')) '私人值、絕對路徑與外部檔名都不能進診斷輸出'
$empty=Get-PowerShellWorkerFailureDiagnostic -SourceRoot $source -TestFile '../private.ps1' -WorkerIndex 0 -Engine pwsh -NativeExitCode -1 -StandardOutputPath (Join-Path $temp 'missing') -StandardErrorPath (Join-Path $temp 'missing2')
Assert ($empty.TestFile -ceq 'unavailable.ps1' -and $empty.CompletedAssertions -eq 0 -and @($empty.Locations).Count -eq 0 -and $empty.NativeExitCode -eq -1) '失敗產物缺失或不合法case只回限型別摘要、不掩蓋原失敗'
$global:LASTEXITCODE=0
