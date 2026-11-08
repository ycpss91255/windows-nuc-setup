#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$fixture=Join-Path $env:TEMP ('worker_context_'+[guid]::NewGuid().ToString('N'))
foreach($dir in @('core','test/powershell/unit','test/powershell/coverage')){[void][IO.Directory]::CreateDirectory((Join-Path $fixture $dir))}
$utf8=[Text.UTF8Encoding]::new($true)
$suite='test/powershell/unit/context_tests.ps1';$wrapper='test/powershell/coverage/safe_suite.ps1'
[IO.File]::WriteAllText((Join-Path $fixture 'core/example.ps1'),"function NativeContextValue {return 7}`n",$utf8)
[IO.File]::WriteAllText((Join-Path $fixture $suite),". (Join-Path ([IO.Path]::GetFullPath((Join-Path `$PSScriptRoot '../../..'))) 'core/example.ps1');if((NativeContextValue) -ne 7){throw 'wrong actual test'}`n",$utf8)
Copy-Item -LiteralPath (Join-Path $root $wrapper) -Destination (Join-Path $fixture $wrapper)
$context=[ordered]@{Commit=('a'*40);RunUrl='https://github.com/example/repo/actions/runs/123';RunAttempt=2;ShardIndex=1;ShardCount=2;GlobalIndices=@(3)}
$manifest=[ordered]@{SourceRoot=$fixture;Sources=@('core/example.ps1');Tests=@($suite);TestEngines=@{};Wrapper=$wrapper;ShardContext=$context}
$input=Join-Path $fixture 'manifest.json';[IO.File]::WriteAllText($input,($manifest|ConvertTo-Json -Depth 8),[Text.UTF8Encoding]::new($false))
$output=Join-Path $fixture 'proof'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'script/test/powershell_coverage.ps1') -ManifestPath $input -OutputDirectory $output *> (Join-Path $fixture 'private.log')
Assert ($LASTEXITCODE -eq 0) '原生Pester worker確實執行該suite成功'
$worker=Get-Content -LiteralPath (Join-Path $output 'worker_0.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert ($null -ne $worker.Context) '原始worker必須親自記錄測試與runcontext，不可由pack貼標'
Assert ($worker.Context.TestFile -ceq $suite -and $worker.Context.TestSHA256 -ceq (Get-FileHash (Join-Path $fixture $suite)).Hash.ToLowerInvariant()) '實際執行suite與當場SHA綁在原始worker內'
Assert ($worker.Context.WrapperFile -ceq $wrapper -and $worker.Context.WrapperSHA256 -ceq (Get-FileHash (Join-Path $fixture $wrapper)).Hash.ToLowerInvariant()) '實際Pester wrapper來源與當場SHA不能替換'
Assert ($worker.Context.Commit -ceq $context.Commit -and $worker.Context.RunUrl -ceq $context.RunUrl -and $worker.Context.RunAttempt -eq 2 -and $worker.Context.GlobalIndex -eq 3 -and $worker.Context.ShardIndex -eq 1 -and $worker.Context.ShardCount -eq 2 -and $worker.Context.ProcessId -eq $worker.ProcessId) '原始程序身分與commit/run/attempt/分片globalindex完整保存'
$global:LASTEXITCODE=0
