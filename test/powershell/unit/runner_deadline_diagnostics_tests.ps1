#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/docker/runner_daemon_library.ps1')
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
$hosted=@{GITHUB_ACTIONS='true';RUNNER_ENVIRONMENT='github-hosted';RUNNER_OS='Windows'}
foreach($category in @('cleanup-process-active','cleanup-budget-exhausted','cleanup-output-incomplete','cleanup-operation-error')){
 $script:calls=@();$script:kind=$category;$record=$null
 try{Wait-HostedWindowsDocker -Identity $hosted -InvokeNative {param($f,$a,$t);$script:calls+=@($f);throw [InvalidOperationException]::new('runner-'+$script:kind)}}catch{$record=$_}
 Assert ($null -ne $record -and $record.Exception.Message -match ('category='+$category+'\b') -and $record.Exception.Message -notmatch 'PRIVATE|Users|stderr' -and $null -eq $record.Exception.InnerException) ('cleanup 診斷分類且不洩漏原文 '+$category)
 Assert ($script:calls.Count -eq 1 -and $script:calls[0] -eq 'docker.exe') 'cleanup 不確定時不得操作服務'
}
$script:calls=@();$record=$null
try{Wait-HostedWindowsDocker -Identity $hosted -InvokeNative {param($f,$a,$t);$script:calls+=@($f);throw [Exception]::new('runner-cleanup-process-active PRIVATE_C:\Users\hidden')}}catch{$record=$_}
Assert ($record.Exception.Message -match 'category=native-error\b' -and $record.Exception.Message -notmatch 'PRIVATE|Users|hidden' -and $script:calls.Count -eq 1) '未知例外即使含類似文字仍維持安全失敗'
foreach($wanted in @('probe','query','stop','start')){
 $script:target=$wanted;$script:stopped=$false
 $native={param($File,$Arguments,$TimeoutMilliseconds)
  $stage=if($File -eq 'docker.exe'){'probe'}else{$Arguments[0]}
  if($stage -eq $script:target){return Invoke-RunnerBoundedProcess -File (Join-Path $PSHOME 'powershell.exe') -Arguments @('-NoProfile','-Command','[Console]::Out.Write("PRIVATE_SENTINEL");[Console]::Error.Write("PRIVATE_SENTINEL");Start-Sleep -Seconds 30') -TimeoutMilliseconds $TimeoutMilliseconds}
  if($stage -eq 'probe'){return @{ExitCode=1;Output='private probe data'}}
  if($stage -eq 'query'){return @{ExitCode=0;Output=('STATE : '+$(if($script:stopped){1}else{4})+' STATE')}}
  if($stage -eq 'stop'){$script:stopped=$true}
  return @{ExitCode=0;Output='private service data'}
 }
 $message='';try{Wait-HostedWindowsDocker -Identity $hosted -DeadlineMilliseconds 5000 -OperationMilliseconds 500 -InvokeNative $native}catch{$message=$_.Exception.Message}
 Assert ($message -match ('stage='+$wanted+'\b') -and $message -match 'category=process-deadline\b' -and $message -match 'elapsed_ms=\d+' -and $message -match 'remaining_ms=\d+') ('owned timeout identifies bounded stage '+$wanted)
 Assert ($message -notmatch 'private|powershell|Users|System32|PRIVATE_SENTINEL') 'diagnostic excludes private process details'
}
$outputDeadline='';try{Wait-HostedWindowsDocker -Identity $hosted -InvokeNative {throw [TimeoutException]::new('runner-output-deadline')}}catch{$outputDeadline=$_.Exception.Message}
Assert ($outputDeadline -match 'stage=probe\b' -and $outputDeadline -match 'category=output-deadline\b') 'output drain deadline is distinct from process deadline'
$secret='PRIVATE_C:\Users\hidden\stderr'
$failed='';$record=$null;try{Wait-HostedWindowsDocker -Identity $hosted -InvokeNative {throw [Exception]::new($secret,[Exception]::new($secret))}}catch{$record=$_;$failed=$_.Exception.Message}
Assert (($record|Out-String) -notmatch 'PRIVATE_C:|hidden|stderr' -and $null -eq $record.Exception.InnerException -and $record.Exception.Data.Count -eq 0) 'error record carries no private nested details'
Assert ($failed -match 'stage=probe\b' -and $failed -match 'category=native-error\b' -and $failed -notmatch 'PRIVATE|Users|stderr') 'unknown native exception is sanitized and remains failure'
$script:clock=0L;$calls=0
$failed='';try{Wait-HostedWindowsDocker -Identity $hosted -DeadlineMilliseconds 10 -OperationMilliseconds 10 -Clock {return $script:clock} -Pause {param($ms);$script:clock+=$ms} -InvokeNative {param($f,$a,$t);if($f -eq 'docker.exe'){return @{ExitCode=1;Output=''}};return @{ExitCode=0;Output='STATE : 2 STATE'}}}catch{$failed=$_.Exception.Message}
Assert ($failed -match 'category=total-deadline\b' -and $failed -notmatch 'PRIVATE') 'total budget exhaustion is bounded and classified'
$ready={return @{ExitCode=0;Output='{"OSType":"windows"}'}}
$success=$true;try{Wait-HostedWindowsDocker -Identity @{} -InvokeNative $ready}catch{$success=$false}
Assert $success 'successful engine remains accepted without recovery'
$denied=$false;try{Wait-HostedWindowsDocker -Identity @{} -InvokeNative {return @{ExitCode=7;Output='PRIVATE'}}}catch{$denied=$true}
Assert $denied 'nonzero engine result and nonhosted identity remain failure'
$ownedParent=(Get-Item -LiteralPath $env:TEMP -Force).FullName;$ownedName='runner_native_'+[guid]::NewGuid().ToString('N');$owned=Join-Path $ownedParent $ownedName
$null=New-Item -ItemType Directory -Path $owned
try {
 Add-Type -OutputAssembly (Join-Path $owned 'docker.exe') -OutputType ConsoleApplication -TypeDefinition 'using System; public class Fake { public static int Main(){ Console.Out.Write("PRIVATE_SENTINEL"); Console.Error.Write("PRIVATE_SENTINEL"); return 5; } }'
 $oldPath=$env:PATH;$oldActions=$env:GITHUB_ACTIONS;$oldPreference=$ErrorActionPreference
 try {
  $env:PATH=$owned+';'+$oldPath;$env:GITHUB_ACTIONS='';$ErrorActionPreference='Continue'
  $output=@(& (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'script/docker/runner_daemon.ps1') 2>&1 | ForEach-Object {[string]$_});$code=$LASTEXITCODE
 }finally{$env:PATH=$oldPath;$env:GITHUB_ACTIONS=$oldActions;$ErrorActionPreference=$oldPreference}
 Assert ($code -ne 0 -and ($output -join ' ') -notmatch 'PRIVATE_SENTINEL|Users|System32') 'actual entry fails without leaking native stdout stderr or private paths'
 Copy-Item -LiteralPath (Join-Path $root 'script/docker/runner_daemon.ps1') -Destination (Join-Path $owned 'entry.ps1')
 [IO.File]::WriteAllText((Join-Path $owned 'runner_daemon_library.ps1'), 'function Wait-HostedWindowsDocker { throw ("Docker readiness stage=probe category="+$env:OWNED_CLEANUP_CATEGORY+" elapsed_ms=1 remaining_ms=999") }')
 $oldPath=$env:PATH;$oldCategory=$env:OWNED_CLEANUP_CATEGORY;$oldPreference=$ErrorActionPreference
 try {
  $env:PATH=$owned+';'+$oldPath;$ErrorActionPreference='Continue'
  foreach($category in @('cleanup-process-active','cleanup-budget-exhausted','cleanup-output-incomplete','cleanup-operation-error')){
   $env:OWNED_CLEANUP_CATEGORY=$category
   $output=@(& (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File (Join-Path $owned 'entry.ps1') 2>&1 | ForEach-Object {[string]$_});$code=$LASTEXITCODE
   Assert ($code -eq 1 -and ($output -join ' ') -match ('category='+$category+'\b') -and ($output -join ' ') -notmatch 'PRIVATE_SENTINEL|Users|System32') ('entry preserves safe cleanup category and failure '+$category)
  }
 } finally {$env:PATH=$oldPath;$env:OWNED_CLEANUP_CATEGORY=$oldCategory;$ErrorActionPreference=$oldPreference}
}finally{
 . (Join-Path $root 'test/powershell/support/runner_fixture.ps1')
 $checked=Assert-RunnerOwnedDirectory -Path $owned -Parent $ownedParent -Name $ownedName
 Remove-Item -LiteralPath $checked -Recurse -Force
}
