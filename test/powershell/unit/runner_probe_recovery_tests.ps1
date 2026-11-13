#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/docker/runner_daemon_library.ps1')
. (Join-Path $root 'test/powershell/support/runner_probe_diagnostic.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$hosted=@{GITHUB_ACTIONS='true';RUNNER_ENVIRONMENT='github-hosted';RUNNER_OS='Windows'}
$script:calls=@();$script:probes=0;$script:phase='initial';$script:nativeKind='unknown';$script:nativeElapsed=-1L
$pidFile=Join-Path $env:TEMP ('owned_probe_pid_'+[guid]::NewGuid().ToString('N'))
$previousPidFile=$env:OWNED_PROBE_PID_FILE
$env:OWNED_PROBE_PID_FILE=$pidFile
$native={param($File,$Arguments,$TimeoutMilliseconds)
 $script:calls+=@($File+' '+($Arguments -join ' '))
 $script:phase=if($File -eq 'owned-probe'){'probe'}elseif($Arguments[0] -cin @('query','stop','start')){$Arguments[0]}else{'unknown'}
 if($File -eq 'owned-probe'){
  $script:probes++
  if($script:probes -eq 1){
   $timer=[Diagnostics.Stopwatch]::StartNew()
   try {return Invoke-RunnerBoundedProcess -File (Join-Path $PSHOME 'powershell.exe') -Arguments @('-NoProfile','-Command','[IO.File]::WriteAllText($env:OWNED_PROBE_PID_FILE,[string]$PID); Start-Sleep -Seconds 60') -TimeoutMilliseconds $TimeoutMilliseconds}
   catch {$script:nativeKind=Get-RunnerProbeNativeKind $_.Exception;throw}
   finally {$timer.Stop();$script:nativeElapsed=[long]$timer.ElapsedMilliseconds}
  }
  return @{ExitCode=0;Output='{"OSType":"windows"}'}
 }
 if($Arguments[0] -eq 'query') {
  $ownedPid=[int][IO.File]::ReadAllText($pidFile)
  Assert ($null -eq (Get-Process -Id $ownedPid -ErrorAction SilentlyContinue)) '服務查詢前真 owned probe 程序已結束'
  return @{ExitCode=0;Output=('STATE : '+$(if($script:calls -contains 'owned-service stop Docker'){1}else{4})+' STATE')}
 }
 return @{ExitCode=0;Output=''}
}
try {
 $ok=$false
 try {Wait-HostedWindowsDocker -Identity $hosted -DeadlineMilliseconds 5000 -OperationMilliseconds 1000 -InvokeNative $native -DockerFile 'owned-probe' -ServiceFile 'owned-service';$ok=$true}catch{foreach($diagnostic in @(Get-RunnerProbeDiagnostic -Phase $script:phase -HasPid (Test-Path -LiteralPath $pidFile -PathType Leaf) -Message ([string]$_.Exception.Message) -NativeKind $script:nativeKind -NativeElapsedMilliseconds $script:nativeElapsed)){Assert $true $diagnostic}}
 Assert $ok 'owned 初次 probe 確認終止後應允許 hosted 單次恢復並驗證 Windows'
 Assert ($script:nativeKind -ceq 'process-cleaned' -and $script:nativeElapsed -gt 0 -and $script:nativeElapsed -le 5000) '真 owned 阻塞呼叫記錄已清理分類及實際耗時'
 Assert (@($script:calls|Where-Object{$_ -eq 'owned-service stop Docker'}).Count -eq 1 -and @($script:calls|Where-Object{$_ -eq 'owned-service start Docker'}).Count -eq 1 -and $script:probes -eq 2) '精確一次 stop/start 與再次 probe'
} finally {
 if(Test-Path -LiteralPath $pidFile){[IO.File]::Delete($pidFile)}
 $env:OWNED_PROBE_PID_FILE=$previousPidFile
}
function Invoke-BoundaryScenario([string]$Mode,[hashtable]$Identity=$hosted){
 $script:boundaryCalls=@();$script:boundaryProbes=0;$script:now=0L
 $adapter={param($File,$Arguments,$TimeoutMilliseconds)
  $script:boundaryCalls+=@($File+' '+($Arguments -join ' '))
  if($File -eq 'owned-probe'){
   $script:boundaryProbes++
   if($Mode -eq 'unclean'){throw [TimeoutException]::new('runner-process-deadline')}
   if($Mode -eq 'output'){throw [TimeoutException]::new('runner-output-deadline')}
   if($Mode -eq 'spoof'){return @{ExitCode=0;Output='runner-process-deadline-cleaned'}}
   if($Mode -eq 'deadline'){$script:now=1000}
   if($script:boundaryProbes -eq 1 -or $Mode -eq 'again'){throw [TimeoutException]::new('runner-process-deadline-cleaned')}
   return @{ExitCode=0;Output='{"OSType":"windows"}'}
  }
  if($Arguments[0] -eq 'query'){if($Mode -eq 'service-fail'){return @{ExitCode=5;Output=''}};return @{ExitCode=0;Output='STATE : 1 STOPPED'}}
  return @{ExitCode=0;Output=''}
 }
 $ok=$false;try{Wait-HostedWindowsDocker -Identity $Identity -DeadlineMilliseconds 1000 -OperationMilliseconds 500 -InvokeNative $adapter -Clock { $script:now } -Pause {param($ms);$script:now+=$ms} -DockerFile 'owned-probe' -ServiceFile 'owned-service';$ok=$true}catch{}
 return $ok
}
foreach($case in @('unclean','output','deadline','spoof')) {
 Assert (-not (Invoke-BoundaryScenario $case)) ($case+' 必須失敗')
 Assert (@($script:boundaryCalls|Where-Object{$_ -like 'owned-service*'}).Count -eq 0) ($case+' 不操作服務')
}
Assert (-not (Invoke-BoundaryScenario 'clean' @{})) '非 hosted 初次逾時必須失敗'
Assert (@($script:boundaryCalls|Where-Object{$_ -like 'owned-service*'}).Count -eq 0) '非 hosted 不操作服務'
Assert (-not (Invoke-BoundaryScenario 'service-fail')) '服務查詢失敗必須失敗'
Assert (@($script:boundaryCalls|Where-Object{$_ -eq 'owned-service start Docker'}).Count -eq 0) '服務查詢失敗不得啟動'
Assert (-not (Invoke-BoundaryScenario 'again')) '恢復後再次逾時必須失敗'
Assert (@($script:boundaryCalls|Where-Object{$_ -eq 'owned-service start Docker'}).Count -eq 1 -and $script:boundaryProbes -eq 2) '再次逾時不得重複恢復'
