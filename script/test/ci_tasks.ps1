#Requires -Version 5.1
function Invoke-CINative {
 param([Parameter(Mandatory=$true)][string]$File,[string[]]$Arguments=@())
 $previous=$ErrorActionPreference
 try{$ErrorActionPreference='Continue';$global:LASTEXITCODE=0;& $File @Arguments;$code=$LASTEXITCODE}finally{$ErrorActionPreference=$previous}
 if($code -ne 0){$failure=[Exception]::new(('CI command failed: '+$File+' / '+$code));$failure.Data['ExitCode']=$code;throw $failure}
}
function Export-CIPowerShellRawEvidence {
 param([Parameter(Mandatory=$true)][string]$SourceRoot,[Parameter(Mandatory=$true)][string]$RunnerTemp)
 $tool=Join-Path $RunnerTemp 'repo-coverage/repo_coverage_tool.exe'
 $evidence=Join-Path $RunnerTemp 'repo-coverage/powershell'
 if(-not(Test-Path -LiteralPath (Join-Path $evidence 'evidence.json') -PathType Leaf)){Write-Host 'No completed PowerShell raw evidence to export.';return}
 if(-not(Test-Path -LiteralPath $tool -PathType Leaf)){throw 'Completed raw evidence has no export verification tool.'}
 Invoke-CINative -File $tool -Arguments @('export-powershell','--source-root',$SourceRoot,'--evidence-dir',$evidence,'--output-dir',(Join-Path $RunnerTemp 'powershell-raw-public'))
}
function Assert-CIResults {
 param([hashtable]$Results)
 foreach($name in @('Tests','Requirements','Docker','Payload','PowerShellCoverage','Coverage')){if(-not $Results.ContainsKey($name) -or $Results[$name] -cne 'success'){throw ('必要工作失敗、取消或跳過：'+$name)}}
}
function Assert-CIRequiredTools {
 param([switch]$Managed)
 foreach($tool in @('powershell.exe','cmd.exe','git.exe','go.exe')){Get-Command $tool -CommandType Application -ErrorAction Stop|Out-Null}
 Invoke-CINative -File git.exe -Arguments @('--version')
 Invoke-CINative -File go.exe -Arguments @('version')
 if($Managed){
  foreach($tool in @('pwsh.exe','dotnet.exe')){Get-Command $tool -CommandType Application -ErrorAction Stop|Out-Null}
  $version=@(Invoke-CINative -File pwsh.exe -Arguments @('-NoProfile','-Command','$PSVersionTable.PSVersion.ToString()'))
  if(($version -join '').Trim() -cne '7.6.9'){throw 'Pinned PowerShell 7.6.9 required.'}
  $sdk=@(Invoke-CINative -File dotnet.exe -Arguments @('--version'))
  if(($sdk -join '').Trim() -cne '10.0.300'){throw 'Pinned managed SDK 10.0.300 required.'}
 }
}
function Assert-CIDockerFailure {
 param([Parameter(Mandatory=$true)][string]$Image)
 $observed=0
 try{Invoke-CINative -File docker.exe -Arguments @('run','--rm','--isolation','process','--network','none','--entrypoint','powershell.exe',$Image,'-NoProfile','-Command','exit 23')}
 catch{if(-not $_.Exception.Data.Contains('ExitCode')){throw};$observed=[int]$_.Exception.Data['ExitCode']}
 if($observed -ne 23){throw ('Expected real container exit 23; observed '+$observed)}
 $global:LASTEXITCODE=0
}
function Assert-CIContainerReport {
 param([Parameter(Mandatory=$true)][string]$Directory)
 $report=Get-Content -LiteralPath (Join-Path $Directory 'summary.json') -Raw -Encoding UTF8|ConvertFrom-Json
 if($report.Environment -notmatch 'Windows container'){throw '報告未標示實際 Windows 容器環境。'}
}
function Get-CIPortalParameters {
 param([string]$Repository,[string]$OutputDirectory,[string]$EventRef,[string]$RunId,[string]$EventName,[int]$RunAttempt)
 $parameters=@{Repository=$Repository;OutputDirectory=$OutputDirectory}
 if($EventRef -eq 'refs/heads/main'){$parameters.MainRunId=$RunId;if($EventName){$parameters.ExpectedMainEvent=$EventName;$parameters.ExpectedMainAttempt=$RunAttempt}}
 return $parameters
}

function Get-CINestedCoverageDiagnostic {
 param([Parameter(Mandatory=$true)][string]$Path)
 $unavailable='@@SAFE_NESTED_CI@@unavailable'
 try{
  if(-not(Test-Path -LiteralPath $Path -PathType Leaf -ErrorAction Stop)){return $unavailable}
  $file=Get-Item -LiteralPath $Path -Force -ErrorAction Stop
  if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Length -gt 4MB){return $unavailable}
  $prefix='PowerShell worker failure diagnostic: '
  $lines=@(Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop | Where-Object {$_.StartsWith($prefix)})
  if($lines.Count -ne 1){return $unavailable}
  $json=$lines[0].Substring($prefix.Length)
  $item=$json|ConvertFrom-Json
  if($item -isnot [pscustomobject] -or ($item|ConvertTo-Json -Depth 5 -Compress) -cne $json){return $unavailable}
  $required=@('SchemaVersion','TestFile','WorkerIndex','Engine','NativeExitCode','CompletedAssertions','FailedAssertionIndices','Locations','ExceptionTypes')
  $properties=@($item.PSObject.Properties.Name)
  if(@($required|Where-Object {$_ -cnotin $properties}).Count -or @($properties|Where-Object {$_ -cnotin ($required+@('PesterFailures'))}).Count){return $unavailable}
  if($item.SchemaVersion -isnot [int] -or $item.SchemaVersion -ne 1 -or $item.TestFile -isnot [string] -or $item.TestFile -cne 'test/powershell/integration/ci_runner_tests.ps1' -or $item.WorkerIndex -isnot [int] -or $item.WorkerIndex -ne 0 -or $item.Engine -isnot [string] -or $item.Engine -cne 'powershell' -or $item.NativeExitCode -isnot [int] -or $item.NativeExitCode -eq 0 -or $item.CompletedAssertions -isnot [int] -or $item.CompletedAssertions -lt 1 -or $item.CompletedAssertions -gt 100000){return $unavailable}
  if($item.FailedAssertionIndices -isnot [array] -or $item.Locations -isnot [array] -or $item.ExceptionTypes -isnot [array] -or $item.Locations.Count -gt 4 -or $item.ExceptionTypes.Count -gt 4){return $unavailable}
  $allowedFiles=@('script/test/ci_runner_library.ps1','script/test/run_ci.ps1','test/powershell/integration/ci_runner_tests.ps1','test/powershell/coverage/safe_suite.ps1')
  foreach($location in $item.Locations){
   if($location -isnot [pscustomobject] -or @($location.PSObject.Properties).Count -ne 2 -or @($location.PSObject.Properties.Name|Where-Object {$_ -cnotin @('File','Line')}).Count -or $location.File -isnot [string] -or $location.File -cnotin $allowedFiles -or $location.Line -isnot [int] -or $location.Line -lt 1 -or $location.Line -gt 1000000){return $unavailable}
  }
  $types=@('RuntimeException','IOException','UnauthorizedAccessException','ArgumentException','ParameterBindingException','CommandNotFoundException','OutOfMemoryException','InvalidOperationException','ParseException')
  foreach($type in $item.ExceptionTypes){if($type -isnot [string] -or $type -cnotin $types){return $unavailable}}
  if('PesterFailures' -cin $properties){
   if($item.PesterFailures -isnot [array] -or $item.PesterFailures.Count -lt 1 -or $item.PesterFailures.Count -gt 16){return $unavailable}
   . (Join-Path $PSScriptRoot 'powershell_worker_diagnostics.ps1')
   $seen=@{}
   foreach($row in $item.PesterFailures){
    if($row -isnot [pscustomobject] -or @($row.PSObject.Properties).Count -ne 4 -or @($row.PSObject.Properties.Name|Where-Object {$_ -cnotin @('Phase','Type','File','Line')}).Count -or $row.Phase -isnot [string] -or $row.Phase -cnotin @('InvokePester','InvokePesterNoResult','ContainerDiscovery','ContainerFailure','BlockLifecycle','TestRun') -or $row.Type -isnot [string] -or $row.Type -cnotin @(Get-PesterDiagnosticTypes) -or $row.File -isnot [string] -or $row.Line -isnot [int] -or $row.Line -lt 0 -or $row.Line -gt 1000000){return $unavailable}
    if($row.File){if($row.File -cnotin $allowedFiles -or $row.Line -lt 1){return $unavailable}}elseif($row.Line -ne 0){return $unavailable}
    if($row.Type -ceq 'NoErrorRecord' -and ($row.Phase -cne 'InvokePesterNoResult' -or $row.File -cne '' -or $row.Line -ne 0)){return $unavailable}
    $key=$row.Phase+'|'+$row.Type+'|'+$row.File+'|'+$row.Line;if($seen.ContainsKey($key)){return $unavailable};$seen[$key]=$true
   }
  }
  $indices=@($item.FailedAssertionIndices)
  if($indices.Count -ne 1 -or $indices[0] -isnot [int] -or $indices[0] -lt 1 -or $indices[0] -gt $item.CompletedAssertions){return $unavailable}
  $type=if($item.ExceptionTypes.Count){$item.ExceptionTypes[0]}else{'unavailable'}
  return ('@@SAFE_NESTED_CI@@worker:'+$indices[0]+':'+$type)
 }catch{return $unavailable}
}
function Write-CIFailureDiagnostics {
 param([Parameter(Mandatory=$true)][string]$ReportDirectory,[ValidateSet('Unit.uac_helpers','Integration.managed_catalog','Integration.collector_self_coverage','Integration.driver_source_coverage','Integration.network_helpers_coverage','Integration.powershell_coverage','Integration.powershell_engine','Integration.uac_updates_coverage','Integration.verification_coverage','Unit.terminal_helpers','Unit.driver_cache_cleanup','Integration.init_runtime','Integration.driver_full_source_coverage','Integration.report_bundle_publication','Integration.ci_runner_coverage')][string[]]$SuiteNames=@('Unit.uac_helpers','Integration.managed_catalog'))
 $directory=[IO.Path]::GetFullPath($ReportDirectory)
 if((Test-Path -LiteralPath $directory) -and ((Get-Item -LiteralPath $directory -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Diagnostic report directory cannot be a reparse point.'}
 foreach($suite in $SuiteNames){
  $name=$suite+'.log';$path=Join-Path $directory $name
  Write-Output ('CI diagnostic: '+$name)
  if($suite -eq 'Integration.ci_runner_coverage'){
   try{
    $file=Get-Item -LiteralPath $path -Force -ErrorAction Stop
    if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Length -gt 4MB){Write-Output '    unavailable';continue}
    $markers=@(Get-Content -LiteralPath $path -Encoding UTF8 -ErrorAction Stop | Where-Object {$_.StartsWith('@@SAFE_NESTED_CI@@')})
    if($markers.Count -eq 1 -and $markers[0] -cmatch '^@@SAFE_NESTED_CI@@worker:([1-9][0-9]{0,5}):(unavailable|RuntimeException|IOException|UnauthorizedAccessException|ArgumentException|ParameterBindingException|CommandNotFoundException|OutOfMemoryException|InvalidOperationException|ParseException)$' -and [int]$Matches[1] -le 100000){Write-Output ('    worker:'+$Matches[1]+':'+$Matches[2])}else{Write-Output '    unavailable'}
   }catch{Write-Output '    unavailable'}
   continue
  }
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){Write-Output '    unavailable';continue}
  if((Get-Item -LiteralPath $path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Diagnostic suite log cannot be a reparse point.'}
  if($suite -eq 'Integration.report_bundle_publication'){
   if((Get-Item -LiteralPath $path).Length -gt 4MB){Write-Output '    unavailable';continue}
   if(@(Get-Content -LiteralPath $path -Encoding UTF8|Where-Object {$_ -ceq '@@SAFE_FIXTURE_DIAG@@fixture_export:go_fixture_failed'}).Count){Write-Output '    fixture_export:go_fixture_failed'}
   continue
  }
  foreach($line in @(Get-Content -LiteralPath $path -Encoding UTF8 -Tail 80)){Write-Output ('    '+$line)}
 }
}
function Write-CIContainerFailureDiagnostics {
 param([Parameter(Mandatory=$true)][string]$ReportDirectory)
 $summary=Join-Path $ReportDirectory 'public/summary.json'
 if(-not(Test-Path -LiteralPath $summary -PathType Leaf)){Write-Output 'Container failure diagnostics unavailable before report generation.';return}
 if((Get-Item -LiteralPath $summary -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Container diagnostic summary cannot be a reparse point.'}
 $report=Get-Content -LiteralPath $summary -Raw -Encoding UTF8|ConvertFrom-Json
 $approved=@('Integration.collector_self_coverage','Integration.driver_source_coverage','Integration.network_helpers_coverage','Integration.powershell_coverage','Integration.powershell_engine','Integration.uac_updates_coverage','Integration.verification_coverage','Unit.terminal_helpers','Unit.driver_cache_cleanup','Integration.init_runtime','Integration.driver_full_source_coverage')
 $failed=@($report.Checks|Where-Object {$_.Name -cin $approved -and $_.Passed -eq $false}|ForEach-Object Name|Select-Object -Unique)
 if($failed.Count){Write-CIFailureDiagnostics -ReportDirectory $ReportDirectory -SuiteNames $failed}
}
