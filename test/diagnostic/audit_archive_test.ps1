#Requires -Version 5.1
$ErrorActionPreference='Stop'
$fixtureRoot=Join-Path ([IO.Path]::GetTempPath()) ('audit-archive-test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixtureRoot)
$priorRunnerTemp=$env:RUNNER_TEMP
try{
 $env:RUNNER_TEMP=$fixtureRoot
 $owned=Join-Path $fixtureRoot 'owned';[void][IO.Directory]::CreateDirectory($owned)
 foreach($name in @('identity.json','worker.xml','stdout.log','planner.exe','unapproved.txt')){[IO.File]::WriteAllText((Join-Path $owned $name),'fixture')}
 # Execute the actual transport's archive statements, rather than a second
 # implementation which could silently disagree with the diagnostic driver.
 $driver=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'audit_discovery.ps1'))
 $start=$driver.IndexOf('Add-Type -AssemblyName System.IO.Compression.FileSystem')
 $end=$driver.IndexOf('if((Get-Item -LiteralPath $zip).Length')
 if($start -lt 0 -or $end -le $start){throw 'Diagnostic archive statements were not found.'}
 & ([scriptblock]::Create($driver.Substring($start,$end-$start)))
 $zips=@(Get-ChildItem -LiteralPath $fixtureRoot -File -Filter '*.zip')
 if($zips.Count -ne 1){throw 'Expected exactly one owned archive.'}
 $archive=[IO.Compression.ZipFile]::OpenRead($zips[0].FullName)
 try{
  $names=@($archive.Entries|ForEach-Object FullName|Sort-Object)
  if(($names -join ',') -cne 'identity.json,stdout.log,worker.xml'){throw 'Archive must preserve JSON/XML/log and exclude EXE/TXT.'}
 }finally{$archive.Dispose()}
 Write-Output 'Native diagnostic archive contract passed.'
}finally{$env:RUNNER_TEMP=$priorRunnerTemp}
