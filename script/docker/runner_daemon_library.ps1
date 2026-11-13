#Requires -Version 5.1
function ConvertTo-RunnerNativeArgument {
 param([string]$Value)
 # Windows CommandLineToArgvW escaping, including quotes and trailing slashes.
 return '"'+[regex]::Replace([regex]::Replace($Value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1')+'"'
}
function Get-RunnerCleanupReserve {
 param([ValidateRange(1,120000)][int]$TimeoutMilliseconds,[bool]$InitialHostedProbe=$false)
 if($InitialHostedProbe){return [int][Math]::Min(2000,[Math]::Floor($TimeoutMilliseconds/4))}
 return 250
}
function Invoke-RunnerBoundedProcess {
 param([string]$File,[string[]]$Arguments,[ValidateRange(1,120000)][int]$TimeoutMilliseconds,[bool]$InitialHostedProbe=$false)
 $watch=[Diagnostics.Stopwatch]::StartNew()
 $cleanupReserve=Get-RunnerCleanupReserve -TimeoutMilliseconds $TimeoutMilliseconds -InitialHostedProbe $InitialHostedProbe
 $started=$false
 $processDeadline=$false
 $process=New-Object Diagnostics.Process
 $process.StartInfo=New-Object Diagnostics.ProcessStartInfo
 $process.StartInfo.FileName=$File
 $process.StartInfo.Arguments=(@($Arguments|ForEach-Object{ConvertTo-RunnerNativeArgument $_}) -join ' ')
 $process.StartInfo.UseShellExecute=$false
 $process.StartInfo.CreateNoWindow=$true
 $process.StartInfo.RedirectStandardOutput=$true
 $process.StartInfo.RedirectStandardError=$true
 try {
  if(-not $process.Start()){throw 'Runner prerequisite process did not start.'}
  $started=$true
  $output=$process.StandardOutput.ReadToEndAsync()
  $errorOutput=$process.StandardError.ReadToEndAsync()
  $remaining=$TimeoutMilliseconds-[int]$watch.ElapsedMilliseconds-$cleanupReserve
  if($remaining -le 0 -or -not $process.WaitForExit([Math]::Max(1,$remaining))){$processDeadline=$true;throw [TimeoutException]::new('runner-process-deadline')}
  $remaining=$TimeoutMilliseconds-[int]$watch.ElapsedMilliseconds-$cleanupReserve
  if($remaining -le 0 -or -not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($output,$errorOutput),[Math]::Max(1,$remaining))){throw [TimeoutException]::new('runner-output-deadline')}
  return @{ExitCode=$process.ExitCode;Output=$output.Result}
 } finally {
  # Never an unbounded WaitForExit/ReadToEnd, even if a tool stops responding.
  try {
   try {
    if($started -and -not $process.HasExited){$process.Kill();$remaining=$TimeoutMilliseconds-[int]$watch.ElapsedMilliseconds;if($remaining -gt 0){$null=$process.WaitForExit([Math]::Min($cleanupReserve,$remaining))}}
   } catch {if($processDeadline){throw [InvalidOperationException]::new('runner-cleanup-operation-error')};throw}
   if($processDeadline){
    try {$exited=$process.HasExited} catch {throw [InvalidOperationException]::new('runner-cleanup-operation-error')}
    if(-not $exited){throw [InvalidOperationException]::new('runner-cleanup-process-active')}
    $remaining=$TimeoutMilliseconds-[int]$watch.ElapsedMilliseconds
    if($remaining -le 0){throw [InvalidOperationException]::new('runner-cleanup-budget-exhausted')}
    try {$drained=[Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($output,$errorOutput),[Math]::Max(1,$remaining))} catch {throw [InvalidOperationException]::new('runner-cleanup-operation-error')}
    if(-not $drained){throw [InvalidOperationException]::new('runner-cleanup-output-incomplete')}
    throw [TimeoutException]::new('runner-process-deadline-cleaned')
   }
  } finally {$process.Dispose()}
 }
}
function Wait-HostedWindowsDocker {
 param([hashtable]$Identity,[ValidateRange(1,120000)][int]$DeadlineMilliseconds=120000,[ValidateRange(1,30000)][int]$OperationMilliseconds=15000,
 [scriptblock]$InvokeNative={param($File,$Arguments,$TimeoutMilliseconds,$InitialHostedProbe);Invoke-RunnerBoundedProcess -File $File -Arguments $Arguments -TimeoutMilliseconds $TimeoutMilliseconds -InitialHostedProbe $InitialHostedProbe},
 [scriptblock]$Clock,[scriptblock]$Pause={param($Milliseconds);Start-Sleep -Milliseconds $Milliseconds},
 [string]$DockerFile='docker.exe',[string]$ServiceFile='sc.exe')
 $watch=[Diagnostics.Stopwatch]::StartNew()
 if(-not $Clock){$Clock={$watch.ElapsedMilliseconds}.GetNewClosure()}
 $started=[long](& $Clock)
 $diagnostic={param([string]$Stage,[string]$Category)
  if($Stage -cnotin @('probe','query','stop','start')){$Stage='probe'}
  if($Category -cnotin @('process-deadline','output-deadline','total-deadline','native-error','cleanup-process-active','cleanup-budget-exhausted','cleanup-output-incomplete','cleanup-operation-error')){$Category='native-error'}
  $elapsed=[Math]::Max(0,[Math]::Min([long]$DeadlineMilliseconds,([long](& $Clock)-$started)))
  $remaining=[Math]::Max(0,[long]$DeadlineMilliseconds-$elapsed)
  throw ('Docker readiness stage='+$Stage+' category='+$Category+' elapsed_ms='+$elapsed+' remaining_ms='+$remaining)
 }
 $hosted=($Identity.GITHUB_ACTIONS -is [string] -and $Identity.RUNNER_ENVIRONMENT -is [string] -and $Identity.RUNNER_OS -is [string] -and $Identity.GITHUB_ACTIONS -ceq 'true' -and $Identity.RUNNER_ENVIRONMENT -ceq 'github-hosted' -and $Identity.RUNNER_OS -ceq 'Windows')
 $call={param($Stage,$File,$Arguments,[bool]$AllowCleanedTimeout=$false)
  $remaining=$DeadlineMilliseconds-([long](& $Clock)-$started)
  if($remaining -le 0){& $diagnostic $Stage 'total-deadline'}
  try{& $InvokeNative $File $Arguments ([int][Math]::Min($OperationMilliseconds,$remaining)) ([bool]($AllowCleanedTimeout -and $hosted))}catch{
   $category='native-error';$exception=$_.Exception
   while($exception){
    if($exception -is [InvalidOperationException] -and $exception.Message -cin @('runner-cleanup-process-active','runner-cleanup-budget-exhausted','runner-cleanup-output-incomplete','runner-cleanup-operation-error')){$category=$exception.Message.Substring(7);break}
    if($exception -is [TimeoutException] -and $exception.Message -ceq 'runner-process-deadline-cleaned'){if($AllowCleanedTimeout -and $hosted){return @{ExitCode=1;Output=''}};$category='process-deadline';break}
    if($exception -is [TimeoutException] -and $exception.Message -ceq 'runner-process-deadline'){$category='process-deadline';break}
    if($exception -is [TimeoutException] -and $exception.Message -ceq 'runner-output-deadline'){$category='output-deadline';break}
    $exception=$exception.InnerException
   }
   & $diagnostic $Stage $category
  }
 }
 $pauseWithinBudget={param($Stage)
  $remaining=$DeadlineMilliseconds-([long](& $Clock)-$started)
  if($remaining -le 0){& $diagnostic $Stage 'total-deadline'}
  & $Pause ([int][Math]::Min(500,$remaining))
 }
 $probe={param([bool]$Initial=$false)
  $result=& $call 'probe' $DockerFile @('info','--format','{{json .}}') $Initial
  if($result.ExitCode -ne 0){return $false}
  # PS5 may enumerate a root JSON array and coerce bool/array comparisons.
  if($result.Output -isnot [string] -or -not $result.Output.Trim().StartsWith('{')){throw 'Docker returned invalid engine information.'}
  try{$engine=ConvertFrom-Json -InputObject $result.Output -ErrorAction Stop}catch{throw 'Docker returned invalid engine information.'}
  if($engine -isnot [Management.Automation.PSCustomObject] -or $engine.OSType -isnot [string] -or $engine.OSType -cne 'windows'){throw 'A Windows Docker engine is required; engine switching is forbidden.'}
  return $true
 }
 if(& $probe $true){Write-Host 'Windows Docker daemon is ready.';return}
 if(-not $hosted){throw 'Docker recovery is restricted to GitHub hosted Windows runners.'}
 $state={
  $result=& $call 'query' $ServiceFile @('query','Docker')
  if($result.ExitCode -ne 0){throw 'Docker service query failed; no daemon is installed or reconfigured.'}
  $match=[regex]::Match($result.Output,'(?m)^\s*STATE\s*:\s*([1-7])\s')
  if(-not $match.Success){throw 'Docker service returned an unrecognized state.'}
  return [int]$match.Groups[1].Value
 }
 $current=& $state
 while($current -in @(2,3,5,6)) {& $pauseWithinBudget 'query';$current=& $state}
 if($current -eq 4){
  Write-Host 'Hosted Docker daemon unavailable; attempting one bounded service restart.'
  $result=& $call 'stop' $ServiceFile @('stop','Docker')
  if($result.ExitCode -ne 0){throw 'Docker service stop failed.'}
  do { $current=& $state;if($current -eq 1){break};& $pauseWithinBudget 'query' } while($true)
 }elseif($current -ne 1){throw 'Docker service state is not eligible for recovery.'}
 $result=& $call 'start' $ServiceFile @('start','Docker')
 if($result.ExitCode -ne 0){throw 'Docker service start failed.'}
 do {if(& $probe){Write-Host 'Windows Docker daemon is ready after one hosted service recovery.';return};& $pauseWithinBudget 'probe'} while($true)
}
