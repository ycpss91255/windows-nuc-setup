#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
$library=Join-Path $root 'script/docker/runner_daemon_library.ps1'
Assert (Test-Path -LiteralPath $library) 'hosted Docker 有界就緒檢查可供真 CI 呼叫'
. $library
. (Join-Path $root 'test/powershell/support/runner_fixture.ps1')
$hosted=@{GITHUB_ACTIONS='true';RUNNER_ENVIRONMENT='github-hosted';RUNNER_OS='Windows'}
function Invoke-Scenario([string]$Mode,[hashtable]$Identity=$hosted){
 $script:calls=@();$script:clock=0L;$script:probes=0
 $native={param($File,$Arguments,$TimeoutMilliseconds)
  $script:calls+=@(($File+' '+($Arguments -join ' ')))
  Assert ($TimeoutMilliseconds -gt 0 -and $TimeoutMilliseconds -le 1000) '每次 native 呼叫使用剩餘有限預算'
  if($File -eq 'docker.exe'){
   $script:probes++
   if($Mode -eq 'linux'){return @{ExitCode=0;Output='{"OSType":"linux"}'}}
   if($Mode -eq 'invalid'){return @{ExitCode=0;Output='not json'}}
   $shapes=@{'os-boolean'='{"OSType":true}';'os-empty-array'='{"OSType":[]}';'os-array'='{"OSType":["windows"]}';'root-array'='[{"OSType":"windows"}]';'root-boolean'='true';'os-missing'='{}';'os-null'='{"OSType":null}'}
   if($shapes.ContainsKey($Mode)){return @{ExitCode=0;Output=$shapes[$Mode]}}
   if($Mode -eq 'throw'){throw 'owned native process timed out'}
   if($Mode -eq 'ready' -or ($script:probes -gt 1 -and $Mode -in @('running','stopped'))){return @{ExitCode=0;Output='{"OSType":"windows"}'}}
   return @{ExitCode=1;Output='private error must not become success'}
  }
  if($Mode -eq 'denied'){return @{ExitCode=5;Output='denied'}}
  if($Mode -eq 'missing'){return @{ExitCode=1060;Output='missing'}}
  if($Arguments[0] -eq 'query'){
   $state=if($Mode -eq 'stopped' -or ($script:calls -contains 'sc.exe stop Docker')){1}else{4}
   if($Mode -eq 'pending'){$state=2}
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
foreach($shape in @('os-boolean','os-empty-array','os-array','root-array','root-boolean','os-missing','os-null')){
 Assert (-not(Invoke-Scenario $shape @{})) ('真 Windows 就緒只接受單一 JSON object 及實際 string OSType：'+$shape)
 Assert ($script:calls.Count -eq 1) '未知 metadata 立即失敗而不嘗試服務恢復'
}
foreach($mode in @('linux','invalid','throw','missing','denied','action-fail','pending','never')){
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
$ownedParent=(Get-Item -LiteralPath $env:TEMP -Force).FullName
$ownedName='runner_native_'+[guid]::NewGuid().ToString('N')
$owned=Join-Path $ownedParent $ownedName
$null=New-Item -ItemType Directory -Path $owned
try {
 $fake=Join-Path $owned 'probe.exe'
 Add-Type -OutputAssembly $fake -OutputType ConsoleApplication -TypeDefinition @'
using System;
using System.IO;
using System.Diagnostics;
using System.Threading;
public class Probe {
 public static int Main(string[] a) {
  if(Path.GetFileName(System.Reflection.Assembly.GetExecutingAssembly().Location)=="docker.exe") {var full=new string[a.Length+1];full[0]="docker.exe";Array.Copy(a,0,full,1,a.Length);a=full;}
  string folder=Environment.GetEnvironmentVariable("OWNED_DOCKER_PROBE");
  string mode=File.ReadAllText(Path.Combine(folder,"mode"));
  File.AppendAllText(Path.Combine(folder,"calls"),string.Join(" ",a)+"\n");
  if(mode=="pipe") {
   var p=new ProcessStartInfo(Environment.GetEnvironmentVariable("OWNED_POWERSHELL"),"-NoProfile -Command Start-Sleep -Seconds 8");
   p.UseShellExecute=false;p.CreateNoWindow=true;p.WindowStyle=ProcessWindowStyle.Hidden;var child=Process.Start(p);
   File.WriteAllText(Path.Combine(folder,"child"),child.Id.ToString()+"|"+child.StartTime.ToUniversalTime().Ticks.ToString());
   return 0;
  }
  string calls=File.ReadAllText(Path.Combine(folder,"calls"));
  if(a[0]=="docker.exe") {
   if(mode=="probe-hang")Thread.Sleep(60000);
   if(mode=="linux"){Console.Write("{\"OSType\":\"linux\"}");return 0;}
   if(mode=="ready" || ((mode=="running"||mode=="stopped") && calls.Contains("sc.exe start Docker"))){Console.Write("{\"OSType\":\"windows\"}");return 0;}
   return 1;
  }
  if(mode=="denied")return 5;
  if(mode=="missing")return 1060;
  if(a[1]=="query") {if(mode=="query-hang")Thread.Sleep(60000);Console.Write("STATE : "+((mode=="stopped"||calls.Contains("sc.exe stop Docker"))?"1":"4")+" STATE");return 0;}
  if(mode=="start-fail" && a[1]=="start")return 5;
  if(mode=="stop-hang" && a[1]=="stop")Thread.Sleep(60000);
  if(mode=="start-hang" && a[1]=="start")Thread.Sleep(60000);
  return 0;
 }
}
'@
 $previousProbe=$env:OWNED_DOCKER_PROBE;$previousPowerShell=$env:OWNED_POWERSHELL
 $env:OWNED_DOCKER_PROBE=$owned;$env:OWNED_POWERSHELL=Join-Path $PSHOME 'powershell.exe'
 try {
  foreach($mode in @('ready','running','stopped','linux','missing','denied','start-fail','probe-hang','query-hang','stop-hang','start-hang','never')){
   [IO.File]::WriteAllText((Join-Path $owned 'mode'),$mode);[IO.File]::WriteAllText((Join-Path $owned 'calls'),'')
   $adapter={param($File,$Arguments,$TimeoutMilliseconds);Invoke-RunnerBoundedProcess -File $fake -Arguments (@($File)+$Arguments) -TimeoutMilliseconds $TimeoutMilliseconds}
   $nativeOk=$false;$timer=[Diagnostics.Stopwatch]::StartNew()
   try{Wait-HostedWindowsDocker -Identity $hosted -DeadlineMilliseconds 2500 -OperationMilliseconds 1000 -InvokeNative $adapter;$nativeOk=$true}catch{}
   Assert ($nativeOk -eq ($mode -in @('ready','running','stopped'))) ('真 owned native 退出碼與恢復行為：'+$mode)
   Assert ($timer.ElapsedMilliseconds -lt 4000) '真 native probe/sc 阻塞仍在整體有界期限結束'
   $calls=[IO.File]::ReadAllLines((Join-Path $owned 'calls'))
   Assert (@($calls|Where-Object{$_ -eq 'sc.exe start Docker'}).Count -le 1 -and @($calls|Where-Object{$_ -eq 'sc.exe stop Docker'}).Count -le 1) '真 native 恢復命令至多各一次'
  }
  [IO.File]::WriteAllText((Join-Path $owned 'mode'),'pipe')
  $timer=[Diagnostics.Stopwatch]::StartNew();$pipeFailed=$false
  try{Invoke-RunnerBoundedProcess -File $fake -Arguments @('docker.exe') -TimeoutMilliseconds 1500|Out-Null}catch{$pipeFailed=$true}
  Assert ($pipeFailed -and $timer.ElapsedMilliseconds -lt 3000) '父程序已退出但 owned 孫程序持輸出管道仍有界失敗'
  Copy-Item -LiteralPath $fake -Destination (Join-Path $owned 'docker.exe')
  $previousPath=$env:PATH;$previousActions=$env:GITHUB_ACTIONS;$previousRunner=$env:RUNNER_ENVIRONMENT;$previousOS=$env:RUNNER_OS
  try {
   $env:PATH=$owned+';'+$previousPath;$env:GITHUB_ACTIONS='';$env:RUNNER_ENVIRONMENT='';$env:RUNNER_OS=''
   foreach($mode in @('ready','linux','never')){
    [IO.File]::WriteAllText((Join-Path $owned 'mode'),$mode)
    # The production entry resolves this owned docker.exe; no real service path is reached.
    $entry=Invoke-RunnerBoundedProcess -File (Join-Path $PSHOME 'powershell.exe') -Arguments @('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $root 'script/docker/runner_daemon.ps1')) -TimeoutMilliseconds 10000
    Assert (($entry.ExitCode -eq 0) -eq ($mode -eq 'ready')) ('真入口保留 native 失敗並將成功歸零：'+$mode)
   }
  }finally{$env:PATH=$previousPath;$env:GITHUB_ACTIONS=$previousActions;$env:RUNNER_ENVIRONMENT=$previousRunner;$env:RUNNER_OS=$previousOS}
 }finally{
  $childFile=Join-Path $owned 'child'
  if(Test-Path -LiteralPath $childFile){
   $identity=[IO.File]::ReadAllText($childFile).Split('|');$childId=0;$startTicks=0L
   if($identity.Count -ne 2 -or -not [int]::TryParse($identity[0],[ref]$childId) -or -not [long]::TryParse($identity[1],[ref]$startTicks)){throw 'Invalid owned child identity.'}
   $child=Get-Process -Id $childId -ErrorAction SilentlyContinue
   if($child){try{if(Test-RunnerProcessIdentity -Process $child -Identifier $childId -StartTicks $startTicks){$child.Kill()}}finally{$child.Dispose()}}
  }
  $env:OWNED_DOCKER_PROBE=$previousProbe;$env:OWNED_POWERSHELL=$previousPowerShell
 }
}finally{
 $checked=Assert-RunnerOwnedDirectory -Path $owned -Parent $ownedParent -Name $ownedName
 Remove-Item -LiteralPath $checked -Recurse -Force
}
