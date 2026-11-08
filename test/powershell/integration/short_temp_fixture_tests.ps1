#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
$fixture=Join-Path ([IO.Path]::GetFullPath($env:TEMP)) ('st_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
$cmd=Join-Path ([Environment]::GetFolderPath('Windows')) 'System32/cmd.exe'
$priorVariable=$env:WINDOWS_SETUP_SHORT_TEMP_FIXTURE;$priorTemp=$env:TEMP
try{
 $nested=Join-Path $fixture 't';[void][IO.Directory]::CreateDirectory($nested)
 $env:WINDOWS_SETUP_SHORT_TEMP_FIXTURE=$nested
 $short=@(& $cmd /d /v:off /c 'for %I in ("%WINDOWS_SETUP_SHORT_TEMP_FIXTURE%") do @echo %~sI')[0]
 if($LASTEXITCODE -ne 0 -or -not(Test-Path -LiteralPath $short -PathType Container)){throw 'Cannot resolve existing fixture directory.'}
 $env:TEMP=$short
 foreach($suite in @('unit/provisioning_context_gap_tests.ps1','unit/provisioning_runtime_gap_tests.ps1','unit/stage_runtime_gap_tests.ps1','unit/driver_release_assets_tests.ps1','integration/driver_release_staging_tests.ps1','unit/driver_cache_cleanup_tests.ps1','integration/init_runtime_tests.ps1')){
  $log=Join-Path $fixture ((Split-Path $suite -Leaf)+'.private.log')
  $ErrorActionPreference='Continue'
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'test/powershell/support/short_temp_child.ps1') -SuitePath (Join-Path $root ('test/powershell/'+$suite)) -SourceRoot $root *> $log
  $code=$LASTEXITCODE;$ErrorActionPreference='Stop'
  $diagnostic=''
  if($code -ne 0){
   $case=0;$failedCase=0
   foreach($line in @(Get-Content -LiteralPath $log -Encoding UTF8 -Tail 256)){
    if($line -match '^@@ASSERT@@(.+)$'){try{$record=$Matches[1]|ConvertFrom-Json;$case++;if($record.Passed -is [bool] -and -not $record.Passed){$failedCase=$case}}catch{}}
    if($line -match '^@@SHORT_TEMP_ERROR@@(.+)$'){
     try{
      $record=$Matches[1]|ConvertFrom-Json
      if($record.Type -cin @('RuntimeException','PathTooLongException','DirectoryNotFoundException','FileNotFoundException','UnauthorizedAccessException','MethodInvocationException','ItemNotFoundException','IOException','ParameterBindingException','OtherException') -and $record.Reason -ceq 'ChildException' -and ($record.Source -ceq 'outside_source' -or $record.Source -cmatch '^(core|modules|script|test)/[a-z0-9_/.-]+\.ps1$') -and $record.Line -ge 0 -and $record.Line -lt 100000 -and $record.InnerType -cin @('None','ArgumentException','PathTooLongException','DirectoryNotFoundException','FileNotFoundException','UnauthorizedAccessException','IOException','NotSupportedException','SecurityException','OtherException') -and [string]$record.HResult -match '^-?\d+$' -and [string]$record.InnerHResult -match '^-?\d+$' -and [long]$record.HResult -ge [int]::MinValue -and [long]$record.HResult -le [int]::MaxValue -and [long]$record.InnerHResult -ge [int]::MinValue -and [long]$record.InnerHResult -le [int]::MaxValue){$diagnostic='; type='+$record.Type+'; source='+$record.Source+'; line='+$record.Line+'; reason=ChildException; inner-type='+$record.InnerType+'; hresult='+$record.HResult+'; inner-hresult='+$record.InnerHResult}
     }catch{}
    }
   }
   $diagnostic='; child-case='+$failedCase+$diagnostic
  }
  Assert ($code -eq 0) ('真短TEMP別名仍維持原始安全斷言 '+$suite+'; native='+$code+$diagnostic)
 }
}finally{$env:TEMP=$priorTemp;$env:WINDOWS_SETUP_SHORT_TEMP_FIXTURE=$priorVariable}
Write-Host 'ALL PASS: original fixtures under filesystem-provided short TEMP alias; no host settings changed'
