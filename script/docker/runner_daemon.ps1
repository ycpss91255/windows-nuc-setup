#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'runner_daemon_library.ps1')
try {
 $docker=(Get-Command docker.exe -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
 $service=Join-Path $env:SystemRoot 'System32/sc.exe'
 Wait-HostedWindowsDocker -Identity @{GITHUB_ACTIONS=$env:GITHUB_ACTIONS;RUNNER_ENVIRONMENT=$env:RUNNER_ENVIRONMENT;RUNNER_OS=$env:RUNNER_OS} -DockerFile $docker -ServiceFile $service
 exit 0
}catch{
 $message=[string]$_.Exception.Message
 if($message -cnotmatch '^Docker readiness stage=(probe|query|stop|start) category=(process-deadline|output-deadline|total-deadline|native-error) elapsed_ms=[0-9]{1,6} remaining_ms=[0-9]{1,6}$'){$message='Windows Docker readiness failed.'}
 [Console]::Error.WriteLine($message);exit 1
}
