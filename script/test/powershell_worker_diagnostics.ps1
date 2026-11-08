#Requires -Version 5.1
function Get-PowerShellWorkerFailureDiagnostic {
 [CmdletBinding()]
 param([string]$SourceRoot,[string]$TestFile,[int]$WorkerIndex,[ValidateSet('powershell','pwsh')][string]$Engine,[int]$NativeExitCode,[string]$StandardOutputPath,[string]$StandardErrorPath,[string[]]$AllowedFiles=@(),[string]$FailureRecordPath)
 $source=[IO.Path]::GetFullPath($SourceRoot).TrimEnd('\','/')
 if([IO.Path]::IsPathRooted($TestFile) -or $TestFile.StartsWith('/') -or $TestFile -cnotmatch '^[A-Za-z0-9_./-]+\.ps1$' -or $TestFile -match '(^|/)\.\.(/|$)'){$TestFile='unavailable.ps1'}
 $assertions=0;$failed=[Collections.Generic.List[int]]::new();$locations=[Collections.Generic.List[object]]::new();$types=[Collections.Generic.List[string]]::new();$seen=@{}
 foreach($path in @($StandardOutputPath,$StandardErrorPath)){
  if(-not(Test-Path -LiteralPath $path -PathType Leaf)){continue}
  $reader=[IO.File]::OpenText($path)
  try{while($null -ne ($line=$reader.ReadLine())){
  $offset=$line.IndexOf('@@ASSERT@@')
  if($offset -ge 0){try{$item=$line.Substring($offset+10)|ConvertFrom-Json;if($item.Passed -is [bool]){$assertions++;if(-not $item.Passed -and $failed.Count -lt 16){$failed.Add($assertions)}}}catch{}}
  if($offset -lt 0){foreach($match in [regex]::Matches($line,'(?<path>[A-Za-z]:[\\/][^\r\n]*?\.ps1)(?::(?:line\s*)?|,\s*line\s*)(?<line>[0-9]+)')){
   try{$file=[IO.Path]::GetFullPath($match.Groups['path'].Value)}catch{continue};$number=0
   if($file.StartsWith($source+'\',[StringComparison]::OrdinalIgnoreCase) -and [int]::TryParse($match.Groups['line'].Value,[ref]$number) -and $number -gt 0){
    $relative=$file.Substring($source.Length+1).Replace('\','/');$key=$relative+':'+$number
    if($relative -cmatch '^[A-Za-z0-9_./-]+\.ps1$' -and $relative -cin $AllowedFiles -and -not $seen.ContainsKey($key) -and $locations.Count -lt 4){$seen[$key]=$true;$locations.Add([pscustomobject]@{File=$relative;Line=$number})}
   }
  }}
  if($offset -lt 0 -and $line -match 'CategoryInfo\s*:'){foreach($match in [regex]::Matches($line,'\b(RuntimeException|IOException|UnauthorizedAccessException|ArgumentException|ParameterBindingException|CommandNotFoundException|OutOfMemoryException|InvalidOperationException|ParseException)\b')){if(-not $types.Contains($match.Value) -and $types.Count -lt 4){$types.Add($match.Value)}}}
  }}finally{$reader.Dispose()}
 }
 $diagnostic=[pscustomobject]@{SchemaVersion=1;TestFile=$TestFile;WorkerIndex=$WorkerIndex;Engine=$Engine;NativeExitCode=$NativeExitCode;CompletedAssertions=$assertions;FailedAssertionIndices=@($failed);Locations=@($locations);ExceptionTypes=@($types)}
 if($FailureRecordPath -and (Test-Path -LiteralPath $FailureRecordPath -PathType Leaf)){$diagnostic|Add-Member PesterFailures @(Read-PesterWorkerFailureRecord -Path $FailureRecordPath -AllowedFiles $AllowedFiles)}
 return $diagnostic
}

function Read-PesterWorkerFailureRecord {
 param([string]$Path,[string[]]$AllowedFiles)
 if((Get-Item -LiteralPath $Path).Length -gt 32768){throw 'Failure diagnostic exceeds the bounded schema.'}
 $text=[IO.File]::ReadAllText($Path);$value=$text|ConvertFrom-Json
 # Only the exact compact producer representation is accepted. Duplicate JSON
 # members are otherwise silently overwritten by Windows PowerShell 5.1.
 if(($value|ConvertTo-Json -Depth 5 -Compress) -cne $text -or $value -isnot [pscustomobject] -or @($value.PSObject.Properties).Count -ne 2 -or @($value.PSObject.Properties|Where-Object Name -cnotin @('SchemaVersion','Failures')).Count -or $value.SchemaVersion -isnot [int] -or $value.SchemaVersion -ne 1 -or $value.Failures -isnot [array] -or $value.Failures.Count -lt 1 -or $value.Failures.Count -gt 16){throw 'Invalid failure diagnostic schema.'}
 $seen=@{}
 foreach($row in $value.Failures){
  if($row -isnot [pscustomobject] -or @($row.PSObject.Properties).Count -ne 4 -or @($row.PSObject.Properties|Where-Object Name -cnotin @('Phase','Type','File','Line')).Count -or $row.Phase -isnot [string] -or $row.Phase -cnotin @('InvokePester','InvokePesterNoResult','ContainerDiscovery','BlockSetup','TestRun') -or $row.Type -isnot [string] -or $row.Type -cnotin @(Get-PesterDiagnosticTypes) -or $row.File -isnot [string] -or $row.Line -isnot [int] -or $row.Line -lt 0 -or $row.Line -gt 1000000){throw 'Invalid typed failure diagnostic row.'}
  if($row.Type -ceq 'NoErrorRecord' -and ($row.Phase -cne 'InvokePesterNoResult' -or $row.File -cne '' -or $row.Line -ne 0)){throw 'NoErrorRecord cannot claim an exception or location.'}
  if($row.File){if($row.File.Length -gt 300 -or $row.File -cnotmatch '^[A-Za-z0-9_./-]+\.ps1$' -or $row.File.StartsWith('/') -or $row.File -match '(^|/)\.\.(/|$)' -or $row.File -cnotin $AllowedFiles -or $row.Line -lt 1){throw 'Failure diagnostic source is not allowed.'}}elseif($row.Line -ne 0){throw 'Failure diagnostic source is unavailable.'}
  $key=$row.Phase+'|'+$row.Type+'|'+$row.File+'|'+$row.Line
  if($seen.ContainsKey($key)){throw 'Duplicate failure diagnostic row.'};$seen[$key]=$true
 }
 return $value.Failures
}

function Get-PesterDiagnosticTypes {
 return @('Exception','RuntimeException','IOException','UnauthorizedAccessException','ArgumentException','ParameterBindingException','CommandNotFoundException','OutOfMemoryException','InvalidOperationException','ParseException','MethodInvocationException','ActionPreferenceStopException','PipelineStoppedException','NoErrorRecord')
}

function Get-NewPesterInvocationErrors {
 param([Management.Automation.ErrorRecord[]]$PriorErrors,[Management.Automation.ErrorRecord[]]$CurrentErrors,[object[]]$InvocationErrors)
 $observed=[Collections.Generic.List[Management.Automation.ErrorRecord]]::new()
 # The newest automatic errors precede ErrorVariable's earlier pipeline items.
 foreach($candidate in @($CurrentErrors)+@($InvocationErrors)){
  if($candidate -isnot [Management.Automation.ErrorRecord]){continue};$known=$false
  foreach($previous in @($PriorErrors)+@($observed)){if([object]::ReferenceEquals($candidate,$previous)){$known=$true;break}}
  if(-not $known){$observed.Add($candidate);if($observed.Count -ge 16){break}}
 }
 return $observed
}

function Write-PesterWorkerFailureRecord {
 param([string]$Path,[string]$SourceRoot,[string[]]$AllowedFiles,$Result,[Management.Automation.ErrorRecord[]]$InvocationErrors,[switch]$NoResult)
 $rows=[Collections.Generic.List[object]]::new();$seen=@{};$allowed=@{}
 foreach($relative in $AllowedFiles){
  if($relative -cmatch '^[A-Za-z0-9_./-]+\.ps1$' -and -not $relative.StartsWith('/') -and $relative -notmatch '(^|/)\.\.(/|$)'){
   try{$physical=(Get-Item -LiteralPath (Join-Path $SourceRoot $relative) -ErrorAction Stop).FullName;$allowed[$physical]=$relative}catch{}
  }
 }
 function Add-PesterDiagnosticError([string]$Phase,[Management.Automation.ErrorRecord]$ErrorRecord){
  if($null -eq $ErrorRecord -or $rows.Count -ge 16){return}
  $locations=[Collections.Generic.List[object]]::new()
  $info=$ErrorRecord.InvocationInfo
  if($info -and $info.ScriptName -and $info.ScriptLineNumber -gt 0){$locations.Add([pscustomobject]@{Path=$info.ScriptName;Line=$info.ScriptLineNumber})}
  if($ErrorRecord.Exception -is [Management.Automation.ParseException]){foreach($parseError in $ErrorRecord.Exception.Errors){if($parseError.Extent.File -and $parseError.Extent.StartLineNumber -gt 0){$locations.Add([pscustomobject]@{Path=$parseError.Extent.File;Line=$parseError.Extent.StartLineNumber})}}}
  foreach($match in [regex]::Matches([string]$ErrorRecord.ScriptStackTrace,'(?<path>[A-Za-z]:[\\/][^\r\n]*?\.ps1)(?::(?:line\s*)?|,\s*line\s*)(?<line>[0-9]+)')){$locations.Add([pscustomobject]@{Path=$match.Groups['path'].Value;Line=[int]$match.Groups['line'].Value})}
  $safeLocations=@(foreach($location in $locations){try{$physical=(Get-Item -LiteralPath $location.Path -ErrorAction Stop).FullName;if($allowed.ContainsKey($physical) -and $location.Line -le 1000000){[pscustomobject]@{File=$allowed[$physical];Line=[int]$location.Line}}}catch{}})
  if(-not $safeLocations.Count){$safeLocations=@([pscustomobject]@{File='';Line=0})}
  $exception=$ErrorRecord.Exception
  for($depth=0;$null -ne $exception -and $depth -lt 4;$depth++){
   $type=$exception.GetType().Name;if($type -cnotin @(Get-PesterDiagnosticTypes) -or $type -ceq 'NoErrorRecord'){$type='Exception'}
   foreach($location in $safeLocations){$key=$Phase+'|'+$type+'|'+$location.File+'|'+$location.Line;if(-not $seen.ContainsKey($key) -and $rows.Count -lt 16){$seen[$key]=$true;$rows.Add([pscustomobject][ordered]@{Phase=$Phase;Type=$type;File=$location.File;Line=$location.Line})}}
   $exception=$exception.InnerException
  }
 }
 $invocationPhase=if($NoResult){'InvokePesterNoResult'}else{'InvokePester'}
 foreach($errorRecord in $InvocationErrors){Add-PesterDiagnosticError $invocationPhase $errorRecord}
 if($NoResult -and -not $rows.Count){$rows.Add([pscustomobject][ordered]@{Phase='InvokePesterNoResult';Type='NoErrorRecord';File='';Line=0})}
 if($null -ne $Result){foreach($group in @(@{Property='FailedContainers';Phase='ContainerDiscovery'},@{Property='FailedBlocks';Phase='BlockSetup'},@{Property='Failed';Phase='TestRun'})){foreach($failure in @($Result.($group.Property))){foreach($errorRecord in @($failure.ErrorRecord)){Add-PesterDiagnosticError $group.Phase $errorRecord}}}}
 if($rows.Count){[IO.File]::WriteAllText($Path,([ordered]@{SchemaVersion=1;Failures=@($rows)}|ConvertTo-Json -Depth 5 -Compress),[Text.UTF8Encoding]::new($false))}
}
