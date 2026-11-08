#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
$library=Join-Path $root 'script/docker/runner_daemon_library.ps1'
Assert (Test-Path -LiteralPath $library) 'hosted Docker 有界就緒檢查可供真 CI 呼叫'
. $library
$hosted=@{GITHUB_ACTIONS='true';RUNNER_ENVIRONMENT='github-hosted';RUNNER_OS='Windows'}
function Invoke-Scenario([string]$Mode,[hashtable]$Identity=$hosted){
 $script:calls=@();$script:clock=0L;$script:probes=0
 $native={param($File,$Arguments,$TimeoutMilliseconds)
  $script:calls+=@(($File+' '+($Arguments -join ' ')))
  Assert ($TimeoutMilliseconds -gt 0 -and $TimeoutMilliseconds -le 1000) '每次 native 呼叫使用剩餘有限預算'
  if($File -eq 'docker.exe'){
   $script:probes++
   if($Mode -eq 'linux'){return @{ExitCode=0;Output='{"OSType":"linux"}'}}
   if($Mode -eq 'ready' -or ($script:probes -gt 1 -and $Mode -in @('running','stopped'))){return @{ExitCode=0;Output='{"OSType":"windows"}'}}
   return @{ExitCode=1;Output='private error must not become success'}
  }
  if($Mode -eq 'denied'){return @{ExitCode=5;Output='denied'}}
  if($Mode -eq 'missing'){return @{ExitCode=1060;Output='missing'}}
  if($Arguments[0] -eq 'query'){
   $state=if($Mode -eq 'stopped' -or ($script:calls -contains 'sc.exe stop Docker')){1}else{4}
   return @{ExitCode=0;Output=('STATE : '+$state+' STATE')}
  }
  if($Mode -eq 'action-fail'){return @{ExitCode=5;Output='denied'}}
  return @{ExitCode=0;Output='ok'}
 }
 $clock={return $script:clock};$pause={param($Milliseconds);$script:clock+=$Milliseconds}
 $ok=$false;try{Wait-HostedWindowsDocker -Identity $Identity -DeadlineMilliseconds 1000 -OperationMilliseconds 1000 -InvokeNative $native -Clock $clock -Pause $pause;$ok=$true}catch{}
 return $ok
}
Assert (Invoke-Scenario ready) '既有 Windows daemon 直接通過'
Assert (@($script:calls|Where-Object{$_ -like 'sc.exe*'}).Count -eq 0) '已就緒時完全不查改服務'
Assert (Invoke-Scenario running) 'named pipe 尚未就緒的 Running 服務可一次重啟後確認 Windows'
Assert (@($script:calls|Where-Object{$_ -eq 'sc.exe stop Docker'}).Count -eq 1 -and @($script:calls|Where-Object{$_ -eq 'sc.exe start Docker'}).Count -eq 1) 'Running 僅一次 stop 與一次 start'
Assert (Invoke-Scenario stopped) 'Stopped 服務可一次啟動後確認 Windows'
Assert (@($script:calls|Where-Object{$_ -eq 'sc.exe stop Docker'}).Count -eq 0 -and @($script:calls|Where-Object{$_ -eq 'sc.exe start Docker'}).Count -eq 1) 'Stopped 不重啟而僅一次 start'
foreach($mode in @('linux','missing','denied','action-fail','never')){
 Assert (-not(Invoke-Scenario $mode)) ('錯 OS／服務失敗／期限保持失敗：'+$mode)
 Assert (@($script:calls|Where-Object{$_ -eq 'sc.exe start Docker'}).Count -le 1) '所有失敗不重複恢復'
}
foreach($identity in @(@{},@{GITHUB_ACTIONS='true';RUNNER_ENVIRONMENT='self-hosted';RUNNER_OS='Windows'},@{GITHUB_ACTIONS='true';RUNNER_ENVIRONMENT='github-hosted';RUNNER_OS='Linux'})){
 Assert (-not(Invoke-Scenario running $identity)) '非 hosted Windows 不取得服務恢復權限'
 Assert (@($script:calls|Where-Object{$_ -like 'sc.exe*'}).Count -eq 0) '本機與 self-hosted 零服務呼叫'
}
$watch=[Diagnostics.Stopwatch]::StartNew();$timedOut=$false
try{Invoke-RunnerBoundedProcess -File (Join-Path $PSHOME 'powershell.exe') -Arguments @('-NoProfile','-Command','Start-Sleep -Seconds 60') -TimeoutMilliseconds 250|Out-Null}catch{$timedOut=$true}
Assert ($timedOut -and $watch.ElapsedMilliseconds -lt 5000) '真 owned 睡眠子程序在期限內被終止並傳遞失敗'
$result=Invoke-RunnerBoundedProcess -File (Join-Path $PSHOME 'powershell.exe') -Arguments @('-NoProfile','-Command','[Console]::Out.Write((''x''*100000));[Console]::Error.Write((''y''*100000));exit 17') -TimeoutMilliseconds 10000
Assert ($result.ExitCode -eq 17 -and $result.Output.Length -eq 100000) '真 owned 大量雙管輸出不死鎖且保留非零退出碼'
