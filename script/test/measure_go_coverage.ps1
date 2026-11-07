#Requires -Version 5.1
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$SourceRoot,[Parameter(Mandatory=$true)][string]$ReportDirectory,[Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../docker/acceptance.ps1')
$source=[IO.Path]::GetFullPath($SourceRoot).TrimEnd('\','/')
$output=[IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\','/')
if($output -ieq $source -or $output.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Coverage output must stay outside the source checkout.'}
if(Test-Path -LiteralPath $output){throw 'Coverage output must be a new directory.'}
$private=Join-Path $env:TEMP ('go_coverage_'+[guid]::NewGuid().ToString('N'))
$counter=Join-Path $private 'cli';New-Item -ItemType Directory $counter -Force|Out-Null
$unit=Join-Path $private 'unit.out';$cli=Join-Path $private 'cli.out'
$previous=$env:WINDOWS_SETUP_CLI_COVERAGE_DIR
try {
 Initialize-ContainerGoEnvironment -SourceRoot $source -CacheRoot (Join-Path $private 'cache')
 $env:WINDOWS_SETUP_CLI_COVERAGE_DIR=$counter
 Push-Location $source
 try {
  Invoke-ContainerGo -Arguments @('test','-coverpkg=./script/test/...',('-coverprofile='+$unit),'-count=1','./...')
  Invoke-ContainerGo -Arguments @('tool','covdata','textfmt','-i',$counter,'-o',$cli)
  Invoke-ContainerGo -Arguments @('run','./script/test/go_coverage','--unit-profile',$unit,'--cli-profile',$cli,'--source-root',$source,'--report-dir',([IO.Path]::GetFullPath($ReportDirectory)),'--output-dir',$output)
 } finally {Pop-Location}
} finally {$env:WINDOWS_SETUP_CLI_COVERAGE_DIR=$previous}