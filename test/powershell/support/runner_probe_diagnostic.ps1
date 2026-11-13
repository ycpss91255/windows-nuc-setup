#Requires -Version 5.1
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
  if($Exception.Message -ceq 'Runner prerequisite process cleanup failed.'){return 'cleanup-unconfirmed'}
  $Exception=$Exception.InnerException
 }
 return 'unknown'
}
function Get-RunnerProbeDiagnostic {
 param([string]$Phase,[bool]$HasPid,[string]$Message,[string]$NativeKind,[long]$NativeElapsedMilliseconds=-1)
 if($Phase -cnotin @('initial','probe','query','stop','start')){$Phase='unknown'}
 $category='unknown'
 if($Message -cmatch '^Docker readiness stage=(probe|query|stop|start) category=(process-deadline|output-deadline|total-deadline|native-error) elapsed_ms=[0-9]{1,6} remaining_ms=[0-9]{1,6}$'){$category=$Matches[2]}
 $pidState=if($HasPid){'present'}else{'absent'}
 $lines=@(('probe diagnostic phase='+$Phase),('probe diagnostic pid='+$pidState),('probe diagnostic category='+$category))
 if($NativeElapsedMilliseconds -ge 0){
  if($NativeKind -cnotin @('process-cleaned','process-deadline','output-deadline','cleanup-unconfirmed')){$NativeKind='unknown'}
  $lines+=@(('probe diagnostic native_kind='+$NativeKind),('probe diagnostic native_elapsed_ms='+$NativeElapsedMilliseconds))
 }
 return $lines
}
