#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/docker/runner_daemon_library.ps1')
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
$hosted=@{GITHUB_ACTIONS='true';RUNNER_ENVIRONMENT='github-hosted';RUNNER_OS='Windows'}
foreach($wanted in @('probe','query','stop','start')){
 $script:target=$wanted;$script:stopped=$false
 $native={param($File,$Arguments,$TimeoutMilliseconds)
  $stage=if($File -eq 'docker.exe'){'probe'}else{$Arguments[0]}
  if($stage -eq $script:target){return Invoke-RunnerBoundedProcess -File (Join-Path $PSHOME 'powershell.exe') -Arguments @('-NoProfile','-Command','Start-Sleep -Seconds 30') -TimeoutMilliseconds $TimeoutMilliseconds}
  if($stage -eq 'probe'){return @{ExitCode=1;Output='private probe data'}}
  if($stage -eq 'query'){return @{ExitCode=0;Output=('STATE : '+$(if($script:stopped){1}else{4})+' STATE')}}
  if($stage -eq 'stop'){$script:stopped=$true}
  return @{ExitCode=0;Output='private service data'}
 }
 $message='';try{Wait-HostedWindowsDocker -Identity $hosted -DeadlineMilliseconds 5000 -OperationMilliseconds 500 -InvokeNative $native}catch{$message=$_.Exception.Message}
 Assert ($message -match ('stage='+$wanted+'\b') -and $message -match 'category=process-deadline\b' -and $message -match 'elapsed_ms=\d+' -and $message -match 'remaining_ms=\d+') ('owned timeout identifies bounded stage '+$wanted)
 Assert ($message -notmatch 'private|powershell|Users|System32') 'diagnostic excludes private process details'
}
$secret='PRIVATE_C:\Users\hidden\stderr'
$failed='';$record=$null;try{Wait-HostedWindowsDocker -Identity $hosted -InvokeNative {throw [Exception]::new($secret,[Exception]::new($secret))}}catch{$record=$_;$failed=$_.Exception.Message}
Assert (($record|Out-String) -notmatch 'PRIVATE|Users|stderr' -and $null -eq $record.Exception.InnerException -and $record.Exception.Data.Count -eq 0) 'error record carries no private nested details'
Assert ($failed -match 'stage=probe\b' -and $failed -match 'category=native-error\b' -and $failed -notmatch 'PRIVATE|Users|stderr') 'unknown native exception is sanitized and remains failure'
$script:clock=0L;$calls=0
$failed='';try{Wait-HostedWindowsDocker -Identity $hosted -DeadlineMilliseconds 10 -OperationMilliseconds 10 -Clock {return $script:clock} -Pause {param($ms);$script:clock+=$ms} -InvokeNative {param($f,$a,$t);if($f -eq 'docker.exe'){return @{ExitCode=1;Output=''}};return @{ExitCode=0;Output='STATE : 2 STATE'}}}catch{$failed=$_.Exception.Message}
Assert ($failed -match 'category=total-deadline\b' -and $failed -notmatch 'PRIVATE') 'total budget exhaustion is bounded and classified'
$ready={return @{ExitCode=0;Output='{"OSType":"windows"}'}}
$success=$true;try{Wait-HostedWindowsDocker -Identity @{} -InvokeNative $ready}catch{$success=$false}
Assert $success 'successful engine remains accepted without recovery'
$denied=$false;try{Wait-HostedWindowsDocker -Identity @{} -InvokeNative {return @{ExitCode=7;Output='PRIVATE'}}}catch{$denied=$true}
Assert $denied 'nonzero engine result and nonhosted identity remain failure'
