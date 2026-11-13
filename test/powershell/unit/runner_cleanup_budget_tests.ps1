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
$probeName='owned_probe_'+[guid]::NewGuid().ToString('N')
$exe=Join-Path $env:TEMP ($probeName+'.exe')
try {
 Add-Type -OutputAssembly $exe -OutputType ConsoleApplication -TypeDefinition 'public class OwnedBudgetProbe { public static void Main(){ System.Threading.Thread.Sleep(60000); } }'
 $script:calls=@();$script:probes=0
 $native={param($file,$argsList,$timeout,$initialHostedProbe)
  $script:calls+=@($file)
  if($file -ceq 'owned-probe'){
   $script:probes++
   if($script:probes -eq 1){return Invoke-RunnerBoundedProcess -File $exe -Arguments @() -TimeoutMilliseconds $timeout -InitialHostedProbe $initialHostedProbe}
   return @{ExitCode=0;Output='{"OSType":"windows"}'}
  }
  $processes=@([Diagnostics.Process]::GetProcessesByName($probeName))
  try {Assert ($processes.Count -eq 0) '服務查詢前真 owned probe 已退出'} finally {foreach($p in $processes){$p.Dispose()}}
  if($argsList[0] -ceq 'query'){return @{ExitCode=0;Output='STATE : 1 STOPPED'}}
  return @{ExitCode=0;Output=''}
 }
 $ok=$false
 try{Wait-HostedWindowsDocker -Identity $hosted -DeadlineMilliseconds 5000 -OperationMilliseconds 2000 -InvokeNative $native -DockerFile 'owned-probe' -ServiceFile 'owned-service';$ok=$true}catch{}
 Assert ($ok -and $script:probes -eq 2) '真 owned 阻塞 probe 確認清理後一次恢復並重驗 Windows'
 $script:calls=@();$script:probes=0;$failed=$false
 try{Wait-HostedWindowsDocker -Identity $hosted -DeadlineMilliseconds 1 -OperationMilliseconds 1 -InvokeNative $native -DockerFile 'owned-probe' -ServiceFile 'owned-service'}catch{$failed=$true}
 Assert ($failed -and @($script:calls|Where-Object{$_ -ceq 'owned-service'}).Count -eq 0) '極短總預算未確認清理或耗盡時不恢復'
} finally {if(Test-Path -LiteralPath $exe){[IO.File]::Delete($exe)}}
