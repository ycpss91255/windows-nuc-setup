#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('doctor','build','test','test-built','shell')][string]$Action,[string]$ReportDirectory,[ValidateSet('process','hyperv')][string]$Isolation='process',[string]$BuildReceiptPath)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'library.ps1')
$previous=@{}
try {
 $context=Get-ContainerContext -Root (Join-Path $PSScriptRoot '../..') -ReportDirectory $ReportDirectory -Isolation $Isolation
 if(-not(Get-Command docker.exe -ErrorAction SilentlyContinue)){throw 'Docker is not installed or not on PATH. No host configuration was changed.'}
 $info=Invoke-ContainerDocker -Arguments @('info','--format','{{json .}}')
 $engine=($info -join "`n")|ConvertFrom-Json
 if($engine.OSType -cne 'windows'){throw 'A Windows container engine is required; this entry never switches the host engine.'}
 Invoke-ContainerDocker -Arguments @('version')
 Invoke-ContainerDocker -Arguments @('compose','version')
 if($Action -eq 'doctor'){Write-Host 'Windows Docker engine detected. This is a prerequisite check, not a test pass.';exit 0}
 $settings=@{WINDOWS_SETUP_SOURCE=$context.Root;WINDOWS_SETUP_REPORTS=$context.Reports;WINDOWS_SETUP_IMAGE=$context.Image;WINDOWS_SETUP_ISOLATION=$context.Isolation}
 foreach($key in $settings.Keys){$previous[$key]=[Environment]::GetEnvironmentVariable($key,'Process');[Environment]::SetEnvironmentVariable($key,$settings[$key],'Process')}
 $compose=@('compose','--project-name',$context.Project,'--file',(Join-Path $context.Root 'compose.yaml'))
 $configuration=(Invoke-ContainerDocker -Arguments ($compose+@('config','--format','json'))) -join "`n"
 Assert-ContainerCompose -Configuration ($configuration|ConvertFrom-Json) -Isolation $context.Isolation -Image $context.Image
 if($Action -eq 'test-built'){$null=Assert-ContainerBuildReceipt -Context $context -Path $BuildReceiptPath}
 else{Invoke-ContainerDocker -Arguments ($compose+@('build','--pull','tools'))}
 if($Action -eq 'build'){
  if($BuildReceiptPath){Save-ContainerBuildReceipt -Context $context -Path $BuildReceiptPath}
  Write-Host ('Built '+$context.Image);exit 0
 }
 if(Test-Path -LiteralPath $context.Reports){throw 'Report destination must be a new directory to avoid mixing runs.'}
 New-Item -ItemType Directory -Path $context.Reports|Out-Null
 Write-Host ('Container report directory: '+$context.Reports)
 if($Action -in @('test','test-built')){
  Invoke-ContainerDocker -Arguments ($compose+@('run','--rm','--no-deps','-T','tools'))
 }else{
  Invoke-ContainerDocker -Arguments ($compose+@('run','--rm','--no-deps','tools','powershell.exe','-NoLogo','-NoProfile','-NoExit','-Command','git.exe config --global --add safe.directory C:/workspace; if($LASTEXITCODE -ne 0){exit $LASTEXITCODE}; . C:/workspace/script/docker/acceptance.ps1; Initialize-ContainerGoEnvironment -SourceRoot C:/workspace -CacheRoot (Join-Path $env:TEMP (''container_go_''+[guid]::NewGuid().ToString(''N''))); Set-Location C:/workspace'))
 }
 exit 0
}catch{
 Write-Error $_ -ErrorAction Continue
 if($_.Exception.Data.Contains('ExitCode')){exit ([int]$_.Exception.Data['ExitCode'])}
 exit 1
}finally{
 foreach($key in $previous.Keys){[Environment]::SetEnvironmentVariable($key,$previous[$key],'Process')}
}
