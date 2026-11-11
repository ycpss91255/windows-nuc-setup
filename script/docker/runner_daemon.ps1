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
}catch{Write-Error $_ -ErrorAction Continue;exit 1}
