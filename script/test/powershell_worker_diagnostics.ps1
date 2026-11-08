#Requires -Version 5.1
function Get-PowerShellWorkerFailureDiagnostic {
 [CmdletBinding()]
 param([string]$SourceRoot,[string]$TestFile,[int]$WorkerIndex,[ValidateSet('powershell','pwsh')][string]$Engine,[int]$NativeExitCode,[string]$StandardOutputPath,[string]$StandardErrorPath,[string[]]$AllowedFiles=@())
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
 [pscustomobject]@{SchemaVersion=1;TestFile=$TestFile;WorkerIndex=$WorkerIndex;Engine=$Engine;NativeExitCode=$NativeExitCode;CompletedAssertions=$assertions;FailedAssertionIndices=@($failed);Locations=@($locations);ExceptionTypes=@($types)}
}
