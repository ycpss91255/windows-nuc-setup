#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$native=Join-Path ([Environment]::GetFolderPath('System')) 'WindowsPowerShell/v1.0/powershell.exe'
$cmd=Join-Path ([Environment]::GetFolderPath('System')) 'cmd.exe'
$fixture=Join-Path ([IO.Path]::GetFullPath($env:TEMP)) ('short_temp_regression_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
$nested=Join-Path $fixture 'nested_temp_alias';[void][IO.Directory]::CreateDirectory($nested)
$env:WINDOWS_SETUP_SHORT_TEMP_FIXTURE=$nested
$short=@(& $cmd /d /v:off /c 'for %I in ("%WINDOWS_SETUP_SHORT_TEMP_FIXTURE%") do @echo %~sI')[0]
if($LASTEXITCODE -ne 0 -or -not(Test-Path -LiteralPath $short -PathType Container)){throw 'Short alias unavailable'}
$env:TEMP=$short
$failed=$false
foreach($mode in @('Bare','Wrapped')){
 $log=Join-Path $fixture ($mode+'.private.log')
 $suite=Join-Path $root 'test/powershell/unit/stage_runtime_gap_tests.ps1'
 $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File')
 if($mode -ceq 'Bare'){$arguments+=@($suite)}else{$arguments+=@((Join-Path $root 'test/powershell/support/short_temp_child.ps1'),'-SuitePath',$suite,'-SourceRoot',$root)}
 $ErrorActionPreference='Continue'
 & $native @arguments *> $log
 $code=$LASTEXITCODE;$ErrorActionPreference='Stop'
 $index=0;$failedIndex=0;$type='Unknown';$source='unknown';$line=0
 $text=[IO.File]::ReadAllText($log)
 foreach($row in @(Get-Content -LiteralPath $log -Encoding UTF8)){
  if($row -match '^@@ASSERT@@(.+)$'){try{$assertion=$Matches[1]|ConvertFrom-Json;$index++;if($assertion.Passed -is [bool] -and -not $assertion.Passed){$failedIndex=$index}}catch{}}
 }
 foreach($candidate in @('PathTooLongException','DirectoryNotFoundException','FileNotFoundException','UnauthorizedAccessException','MethodInvocationException','ItemNotFoundException','IOException','ParameterBindingException','RuntimeException')){if($text.Contains($candidate)){$type=$candidate;break}}
 $flat=$text.Replace("`r",'').Replace("`n",'')
 $pattern=[regex]::Escape($root.TrimEnd('\')+'\')+'(?<file>(?:core|modules|script|test)[a-z0-9_\\/.-]+\.ps1):(?<line>[0-9]+)'
 $match=[regex]::Match($flat,$pattern)
 if($match.Success){$source=$match.Groups['file'].Value.Replace('\','/');$line=[int]$match.Groups['line'].Value}
 Write-Host ('SAFE_STAGE_PROBE mode='+$mode+'; native='+$code+'; child-case='+$failedIndex+'; completed-asserts='+$index+'; type='+$type+'; source='+$source+'; line='+$line)
 if($code -ne 0){$failed=$true}
}
if($failed){exit 1};exit 0
