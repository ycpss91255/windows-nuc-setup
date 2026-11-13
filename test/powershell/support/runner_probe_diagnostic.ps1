#Requires -Version 5.1
function Test-RunnerOwnedProbeExited {
 param([string]$Name)
 if($Name -cnotmatch '^owned_probe_[0-9a-f]{32}$'){throw 'Invalid owned probe name.'}
 $processes=@([Diagnostics.Process]::GetProcessesByName($Name))
 try {return ($processes.Count -eq 0)} finally {foreach($process in $processes){$process.Dispose()}}
}
function Get-RunnerProbeNativeKind {
 param([Exception]$Exception)
 while($null -ne $Exception){
  if($Exception -is [TimeoutException]){
   switch -CaseSensitive ($Exception.Message){
    'runner-process-deadline-cleaned' {return 'process-cleaned'}
    'runner-process-deadline' {return 'process-deadline'}
    'runner-output-deadline' {return 'output-deadline'}
   }
  }
  if($Exception -is [InvalidOperationException] -and $Exception.Message -cin @('runner-cleanup-process-active','runner-cleanup-budget-exhausted','runner-cleanup-output-incomplete','runner-cleanup-operation-error')){return $Exception.Message.Substring(7)}
  if($Exception.Message -ceq 'Runner prerequisite process cleanup failed.'){return 'cleanup-unconfirmed'}
  $Exception=$Exception.InnerException
 }
 return 'unknown'
}
function Get-RunnerProbeDiagnostic {
 param([string]$Phase,[bool]$HasPid,[string]$Message,[string]$NativeKind,[long]$NativeElapsedMilliseconds=-1)
 if($Phase -cnotin @('initial','probe','query','stop','start')){$Phase='unknown'}
 $category='unknown'
 if($Message -cmatch '^Docker readiness stage=(probe|query|stop|start) category=(process-deadline|output-deadline|total-deadline|native-error|cleanup-process-active|cleanup-budget-exhausted|cleanup-output-incomplete|cleanup-operation-error) elapsed_ms=[0-9]{1,6} remaining_ms=[0-9]{1,6}$'){$category=$Matches[2]}
 $pidState=if($HasPid){'present'}else{'absent'}
 $lines=@(('probe diagnostic phase='+$Phase),('probe diagnostic pid='+$pidState),('probe diagnostic category='+$category))
 if($NativeElapsedMilliseconds -ge 0){
  if($NativeKind -cnotin @('process-cleaned','process-deadline','output-deadline','cleanup-unconfirmed','cleanup-process-active','cleanup-budget-exhausted','cleanup-output-incomplete','cleanup-operation-error')){$NativeKind='unknown'}
  $lines+=@(('probe diagnostic native_kind='+$NativeKind),('probe diagnostic native_elapsed_ms='+$NativeElapsedMilliseconds))
 }
 return $lines
}
