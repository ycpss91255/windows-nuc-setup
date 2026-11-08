#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
$fixture=Join-Path $env:TEMP ('docker_entry_'+[guid]::NewGuid().ToString('N'));$source=Join-Path $fixture 'source'
[void][IO.Directory]::CreateDirectory((Join-Path $source '.git'))
foreach($file in @('dockerfile/windows_tests.dockerfile','script/docker/download_library.ps1','script/docker/install_min_git.ps1','script/docker/install_go.ps1','script/docker/install_managed_tools.ps1','script/docker/container_test.ps1','script/docker/docker.ps1','script/docker/library.ps1','script/test/ci_tasks.ps1','.dockerignore','compose.yaml')){
 $target=Join-Path $source $file;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target));Copy-Item -LiteralPath (Join-Path $root $file) -Destination $target
}
$runner=Join-Path $fixture 'runner.ps1'
$program=@'
param($Entry,$Action,$Receipt,$Reports,$Log,$Mode)
$ErrorActionPreference='Stop'
function git.exe {$global:LASTEXITCODE=0;return ('a'*40)}
function docker.exe {
 $words=@($args);[IO.File]::AppendAllText($Log,((@{Args=$words;Image=$env:WINDOWS_SETUP_IMAGE}|ConvertTo-Json -Compress)+"`n"));$global:LASTEXITCODE=0
 if($words[0] -eq 'info'){return '{"OSType":"windows"}'}
 if($words[0] -eq 'image'){
  if($Mode -eq 'inspect-fail'){$global:LASTEXITCODE=18;return}
  return (@{Id=('sha256:'+('b'*64));RepoTags=@($env:WINDOWS_SETUP_IMAGE)}|ConvertTo-Json -Compress)
 }
 if($words -contains 'config'){return (@{services=@{tools=@{image=$env:WINDOWS_SETUP_IMAGE;isolation='process';build=@{isolation='process'}}}}|ConvertTo-Json -Depth 5 -Compress)}
 if($words -contains 'build' -and $Mode -eq 'build-fail'){$global:LASTEXITCODE=37}
 if($words -contains 'run' -and $Mode -eq 'run-fail'){$global:LASTEXITCODE=29}
}
& $Entry -Action $Action -BuildReceiptPath $Receipt -ReportDirectory $Reports -Isolation process
exit $LASTEXITCODE
'@
[IO.File]::WriteAllText($runner,$program,[Text.UTF8Encoding]::new($true))
$entry=Join-Path $source 'script/docker/docker.ps1';$receipt=Join-Path $fixture 'built.json';$log=Join-Path $fixture 'calls.jsonl'
function Run([string]$Action,[string]$Mode,[string]$ReceiptPath=$receipt){
 $reports=Join-Path $fixture ([guid]::NewGuid().ToString('N'))
 $old=$ErrorActionPreference
 try{$ErrorActionPreference='Continue';& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -Entry $entry -Action $Action -Receipt $ReceiptPath -Reports $reports -Log $log -Mode $Mode *> (Join-Path $fixture 'last.log');$code=$LASTEXITCODE}finally{$ErrorActionPreference=$old}
 return $code
}
Assert ((Run build valid) -eq 0 -and (Test-Path -LiteralPath $receipt)) 'actual build entry writes its receipt only after successful native Docker build'
[IO.File]::WriteAllText($log,'')
Assert ((Run test-built valid) -eq 0) 'actual test-built entry executes complete container route'
$calls=@(Get-Content $log|ForEach-Object {$_|ConvertFrom-Json});$runs=@($calls|Where-Object {$_.Args -ccontains 'run'})
Assert ($runs.Count -eq 1 -and @($calls|Where-Object {$_.Args -ccontains 'build'}).Count -eq 0 -and $runs[0].Image -ceq ('sha256:'+('b'*64)) -and $runs[0].Args -ccontains '--no-build' -and $runs[0].Args -ccontains '--pull' -and $runs[0].Args -ccontains 'never') 'test phase pins inspected immutable image ID and cannot build or pull after verification'
foreach($mode in @('missing','inspect-fail','run-fail')){
 [IO.File]::WriteAllText($log,'');$path=if($mode -eq 'missing'){Join-Path $fixture 'absent.json'}else{$receipt}
 $code=Run test-built $mode $path;$calls=@(Get-Content $log|ForEach-Object {$_|ConvertFrom-Json});$runs=@($calls|Where-Object {$_.Args -ccontains 'run'})
 if($mode -eq 'run-fail'){Assert ($code -eq 29 -and $runs.Count -eq 1) 'actual native test failure retains its exact nonzero process exit'}
 else{Assert ($code -ne 0 -and $runs.Count -eq 0 -and @($calls|Where-Object {$_.Args -ccontains 'build'}).Count -eq 0) ('invalid prerequisite never runs or rebuilds the image: '+$mode)}
}
$failedReceipt=Join-Path $fixture 'failed.json'
Assert ((Run build build-fail $failedReceipt) -eq 37 -and -not(Test-Path $failedReceipt)) 'failed native build cannot emit a successful receipt'
