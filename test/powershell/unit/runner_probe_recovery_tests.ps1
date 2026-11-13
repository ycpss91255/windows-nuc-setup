#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/docker/runner_daemon_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$hosted=@{GITHUB_ACTIONS='true';RUNNER_ENVIRONMENT='github-hosted';RUNNER_OS='Windows'}
$script:calls=@();$script:probes=0
$native={param($File,$Arguments,$TimeoutMilliseconds)
 $script:calls+=@($File+' '+($Arguments -join ' '))
 if($File -eq 'owned-probe'){
  $script:probes++
  if($script:probes -eq 1){return Invoke-RunnerBoundedProcess -File (Join-Path $PSHOME 'powershell.exe') -Arguments @('-NoProfile','-Command','Start-Sleep -Seconds 60') -TimeoutMilliseconds $TimeoutMilliseconds}
  return @{ExitCode=0;Output='{"OSType":"windows"}'}
 }
 if($Arguments[0] -eq 'query') {return @{ExitCode=0;Output=('STATE : '+$(if($script:calls -contains 'owned-service stop Docker'){1}else{4})+' STATE')}}
 return @{ExitCode=0;Output=''}
}
$ok=$false
try {Wait-HostedWindowsDocker -Identity $hosted -DeadlineMilliseconds 5000 -OperationMilliseconds 1000 -InvokeNative $native -DockerFile 'owned-probe' -ServiceFile 'owned-service';$ok=$true}catch{Write-Host ('Observed: '+$_.Exception.Message)}
Assert $ok 'owned 初次 probe 確認終止後應允許 hosted 單次恢復並驗證 Windows'
Assert (@($script:calls|Where-Object{$_ -eq 'owned-service stop Docker'}).Count -eq 1 -and @($script:calls|Where-Object{$_ -eq 'owned-service start Docker'}).Count -eq 1 -and $script:probes -eq 2) '精確一次 stop/start 與再次 probe'
