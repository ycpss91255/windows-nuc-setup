#Requires -Version 5.1
function Get-RunnerProbeDiagnostic {
 param([string]$Phase,[bool]$HasPid,[string]$Message)
 if($Phase -cnotin @('initial','probe','query','stop','start')){$Phase='unknown'}
 $category='unknown'
 if($Message -cmatch '^Docker readiness stage=(probe|query|stop|start) category=(process-deadline|output-deadline|total-deadline|native-error) elapsed_ms=[0-9]{1,6} remaining_ms=[0-9]{1,6}$'){$category=$Matches[2]}
 $pidState=if($HasPid){'present'}else{'absent'}
 return @(('probe diagnostic phase='+$Phase),('probe diagnostic pid='+$pidState),('probe diagnostic category='+$category))
}
