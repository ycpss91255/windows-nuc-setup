#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
. (Join-Path $root 'script/docker/container_health.ps1')
$script:called=0
function Assert-CIRequiredTools {param([switch]$Managed) $script:called++;if(-not $Managed){throw 'managed tool check required'}}
Assert (Test-ContainerToolHealth) 'successful tool responses yield healthy'
Assert ($script:called -eq 1) 'probe checks all managed prerequisites'
function Assert-CIRequiredTools {param([switch]$Managed) throw 'tool failed to respond'}
Assert (-not (Test-ContainerToolHealth)) 'failed tool response yields unhealthy'
$docker=[IO.File]::ReadAllText((Join-Path $root 'dockerfile/windows_tests.dockerfile'))
$ignore=[IO.File]::ReadAllText((Join-Path $root '.dockerignore'))
Assert ($docker -match '(?m)^HEALTHCHECK --interval=30s --timeout=10s --retries=3 CMD ' -and $docker.Contains('Test-ContainerToolHealth') -and $docker.Contains('exit 1')) 'bounded Docker health check propagates failures'
Assert ($docker.Contains('COPY script/docker/container_health.ps1 C:/tools/container_health.ps1') -and $ignore.Contains('!script/docker/container_health.ps1')) 'probe is included in image build context'
Assert ($docker.Contains('"-File", "C:/tools/container_test.ps1"')) 'test command and its exit status remain unchanged'
