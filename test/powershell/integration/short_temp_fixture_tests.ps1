#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
$fixture=Join-Path ([IO.Path]::GetFullPath($env:TEMP)) ('short_temp_regression_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
$cmd=Join-Path ([Environment]::GetFolderPath('Windows')) 'System32/cmd.exe'
$priorVariable=$env:WINDOWS_SETUP_SHORT_TEMP_FIXTURE;$priorTemp=$env:TEMP
try{
 $nested=Join-Path $fixture 'nested_temp_alias';[void][IO.Directory]::CreateDirectory($nested)
 $env:WINDOWS_SETUP_SHORT_TEMP_FIXTURE=$nested
 $short=@(& $cmd /d /v:off /c 'for %I in ("%WINDOWS_SETUP_SHORT_TEMP_FIXTURE%") do @echo %~sI')[0]
 if($LASTEXITCODE -ne 0 -or -not(Test-Path -LiteralPath $short -PathType Container)){throw 'Cannot resolve existing fixture directory.'}
 $env:TEMP=$short
 foreach($suite in @('unit/provisioning_context_gap_tests.ps1','unit/provisioning_runtime_gap_tests.ps1','unit/stage_runtime_gap_tests.ps1','unit/driver_release_assets_tests.ps1','integration/driver_release_staging_tests.ps1','unit/driver_cache_cleanup_tests.ps1','integration/init_runtime_tests.ps1')){
  $log=Join-Path $fixture ((Split-Path $suite -Leaf)+'.private.log')
  $ErrorActionPreference='Continue'
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root ('test/powershell/'+$suite)) *> $log
  $code=$LASTEXITCODE;$ErrorActionPreference='Stop'
  Assert ($code -eq 0) ('真短TEMP別名仍維持原始安全斷言 '+$suite+'; native='+$code)
 }
}finally{$env:TEMP=$priorTemp;$env:WINDOWS_SETUP_SHORT_TEMP_FIXTURE=$priorVariable}
Write-Host 'ALL PASS: original fixtures under filesystem-provided short TEMP alias; no host settings changed'
