#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/docker/library.ps1')
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
function Refuse([scriptblock]$Action,[string]$Message){$caught=$false;try{& $Action|Out-Null}catch{$caught=$true};Assert $caught $Message}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ("container 中文 ' "+[guid]::NewGuid().ToString('N'))
$source=Join-Path $fixture 'source';$reports=Join-Path $fixture 'reports'
New-Item -ItemType Directory (Join-Path $source '.git'),(Join-Path $source 'dockerfile'),(Join-Path $source 'script/docker') -Force|Out-Null
foreach($file in @('dockerfile/windows_tests.dockerfile','script/docker/install_min_git.ps1','script/docker/container_test.ps1','.dockerignore')){Copy-Item -LiteralPath (Join-Path $root $file) -Destination (Join-Path $source $file)}
$first=Get-ContainerContext $source $reports
$again=Get-ContainerContext $source $reports
Assert ($first.Image -ceq $again.Image -and $first.Project -ceq $again.Project) 'same toolchain inputs select the same exact image and project'
Assert ($first.Root -ceq $source -and $first.Reports -ceq $reports) 'spaces Unicode and apostrophe paths remain one value'
Assert (-not(Test-Path $reports)) 'planning never creates or overwrites report destination'
[IO.File]::AppendAllText((Join-Path $source 'script/docker/container_test.ps1'),"`r`n# changed fixture")
$changed=Get-ContainerContext $source $reports
Assert ($changed.Image -cne $first.Image) 'changed runner content cannot reuse stale image tag'
Refuse {Get-ContainerContext $source (Join-Path $source 'reports')} 'report bind cannot be inside read-only source'
Refuse {Get-ContainerContext $source $fixture} 'report bind cannot contain source checkout'
Refuse {Get-ContainerContext $source $source} 'report bind cannot equal source checkout'
$linked=Join-Path $fixture 'linked';New-Item -ItemType Directory $linked|Out-Null;[IO.File]::WriteAllText((Join-Path $linked '.git'),'gitdir: outside')
Refuse {Get-ContainerContext $linked $reports} 'linked worktree git pointer is rejected instead of mounting incomplete history'
# Fake only Docker invocation, proving the native exit status is preserved for callers.
function docker.exe {$global:LASTEXITCODE=37}
$failure=$null;try{Invoke-ContainerDocker -Arguments @('run','fixture')}catch{$failure=$_.Exception}
Assert ($failure -and $failure.Data['ExitCode'] -eq 37) 'failed Docker command retains exact nonzero exit status'
function docker.exe {Write-Output 'fixture-ok';$global:LASTEXITCODE=0}
Assert ((Invoke-ContainerDocker -Arguments @('version')) -eq 'fixture-ok') 'successful Docker output is returned unchanged'
function docker.exe {$script:captured=@($args);$global:LASTEXITCODE=0}
Invoke-ContainerDocker -Arguments @('info','--format','{{json .}}')
Assert ($script:captured.Count -eq 3 -and $script:captured[1] -eq '--format' -and $script:captured[2] -eq '{{json .}}') 'Docker info format argument reaches executable intact'
Invoke-ContainerDocker -Arguments @('compose','version')
Assert (($script:captured -join '|') -eq 'compose|version') 'Compose subcommand is not dropped during argument forwarding'
Remove-Item Function:/docker.exe
