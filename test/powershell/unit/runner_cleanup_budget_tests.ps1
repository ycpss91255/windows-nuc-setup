#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/docker/runner_daemon_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
Assert ($null -ne (Get-Command Get-RunnerCleanupReserve -ErrorAction SilentlyContinue)) '首次 hosted probe 有可驗證的清理預留預算'
foreach($c in @(@{Total=15000;Expected=2000},@{Total=1000;Expected=250},@{Total=3;Expected=0},@{Total=1;Expected=0},@{Total=120000;Expected=2000})){
 $actual=Get-RunnerCleanupReserve -TimeoutMilliseconds $c.Total -InitialHostedProbe $true
 Assert ($actual -eq $c.Expected -and $actual -ge 0 -and $actual -le $c.Total) ('首次 hosted 預留合理且有界 '+$c.Total)
}
Assert ((Get-RunnerCleanupReserve -TimeoutMilliseconds 15000 -InitialHostedProbe $false) -eq 250) '其他操作保留既有 250 毫秒政策'
$hosted=@{GITHUB_ACTIONS='true';RUNNER_ENVIRONMENT='github-hosted';RUNNER_OS='Windows'}
function Invoke-BudgetWiring([hashtable]$Identity){
 $script:records=@();$script:probes=0
 $native={param($file,$argsList,$timeout,$initialHostedProbe)
  $stage=if($file -ceq 'owned-probe'){'probe'}else{$argsList[0]}
  $script:records+=@([pscustomobject]@{Stage=$stage;Initial=$initialHostedProbe;Timeout=$timeout})
  if($stage -ceq 'probe'){$script:probes++;if($script:probes -gt 1){return @{ExitCode=0;Output='{"OSType":"windows"}'}};return @{ExitCode=1;Output=''}}
  if($stage -ceq 'query'){return @{ExitCode=0;Output='STATE : 1 STOPPED'}}
  return @{ExitCode=0;Output=''}
 }
 try {Wait-HostedWindowsDocker -Identity $Identity -DeadlineMilliseconds 5000 -OperationMilliseconds 1000 -InvokeNative $native -DockerFile 'owned-probe' -ServiceFile 'owned-service'} catch {}
}
Invoke-BudgetWiring $hosted
Assert ($script:records.Count -eq 4 -and $script:records[0].Stage -ceq 'probe' -and $script:records[0].Initial -ceq $true) 'hosted 首次真接線攜帶擴大清理預留旗標'
Assert (@($script:records | Select-Object -Skip 1 | Where-Object {$_.Initial -eq $true}).Count -eq 0 -and $script:records[3].Stage -ceq 'probe') '服務及第二次 probe 不套用首次政策'
Invoke-BudgetWiring @{}
Assert ($script:records.Count -eq 1 -and $script:records[0].Initial -ne $true) '非 hosted 首次 probe 不套用新政策亦不操作服務'
