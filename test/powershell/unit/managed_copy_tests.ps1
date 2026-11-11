#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++}
$library=Join-Path $root 'modules/native/managed_source_library.ps1'
Assert (Test-Path -LiteralPath $library -PathType Leaf) 'managed dependency copy has a safely loadable implementation'
. $library
$temp=Join-Path ([IO.Path]::GetTempPath()) ('managed_copy_'+[guid]::NewGuid().ToString('N'))
$source=Join-Path $temp '來源 with spaces';$target=Join-Path $temp 'worker'
New-Item -ItemType Directory -Path (Join-Path $source 'native') -Force|Out-Null
$path=Join-Path $source 'native/example.cs';[IO.File]::WriteAllText($path,'public static class Example { public static int Result(){ return 4; } }')
$copy=Copy-SetupManagedSource -SourceRoot $source -DestinationRoot $target -FileName 'example.cs'
Assert ((Test-Path -LiteralPath $copy -PathType Leaf) -and (Get-FileHash $copy).Hash -eq (Get-FileHash $path).Hash) 'worker receives byte-identical managed source from Unicode and space path'
Assert ((Copy-SetupManagedSource $target $target 'example.cs') -eq $copy) 'already staged source does not copy over itself'
$missing=Join-Path $temp 'absent_destination';$rejected=$false;try{Copy-SetupManagedSource $source $missing 'missing.cs'}catch{$rejected=$true}
Assert ($rejected -and -not(Test-Path $missing)) 'missing source fails before destination creation'
$rejected=$false;try{Copy-SetupManagedSource $source $target '../escape.cs'}catch{$rejected=$true}
Assert $rejected 'managed dependency filename cannot escape native directory'
$script:realCopy=$false
function Copy-Item {param($LiteralPath,$Destination,[switch]$Force,$ErrorAction) [IO.File]::WriteAllText($Destination,'corrupt fixture');$script:realCopy=$true}
$rejected=$false;try{Copy-SetupManagedSource $source $target 'example.cs'}catch{$rejected=$true}
Assert ($rejected -and $script:realCopy) 'copy corruption fails read-back hash verification'
Write-Host ('ALL PASS: '+$script:count+' TEMP managed dependency copy assertions')