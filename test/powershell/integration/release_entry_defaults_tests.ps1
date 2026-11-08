#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
$fixture=Join-Path $env:TEMP ('release_entry_binding_'+[guid]::NewGuid().ToString('N'))
foreach($directory in @('script/release','script/report','script/test','public','unrelated')){[void][IO.Directory]::CreateDirectory((Join-Path $fixture $directory))}
foreach($entry in @('script/release/stage_driver_release.ps1','script/report/publish_quality_release.ps1')){Copy-Item -LiteralPath (Join-Path $root $entry) -Destination (Join-Path $fixture $entry)}
# Only the dot-source boundary is stubbed. Each full, unchanged native entry
# binds its parameters, locates dependencies and passes its actual metadata path.
# Stop at that boundary before any release, network or driver operation.
$stageStub=@'
function Invoke-StageDriverRelease {
 param($Version,$Repository,$AssetDirectory,$MetadataPath,$PackageRoot)
 if([IO.Path]::GetFullPath($MetadataPath) -cne $env:WINDOWS_SETUP_BINDING_EXPECTED){throw 'fixture metadata binding mismatch'}
 if([IO.Path]::GetFullPath($PackageRoot) -cne [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))){throw 'fixture package root mismatch'}
 Write-Output 'FIXTURE_METADATA_BINDING_MATCH';exit 0
}
function gh {throw 'fixture forbids remote commands'}
'@
$publisherStub=@'
function Assert-TestReportSnapshot {
 param($Report,[switch]$Release)
 if([IO.Path]::GetFullPath($DriverAssetManifestPath) -cne $env:WINDOWS_SETUP_BINDING_EXPECTED){throw 'fixture metadata binding mismatch'}
 Write-Output 'FIXTURE_METADATA_BINDING_MATCH';exit 0
}
function gh {throw 'fixture forbids remote commands'}
'@
[IO.File]::WriteAllText((Join-Path $fixture 'script/release/driver_release_library.ps1'),$stageStub)
[IO.File]::WriteAllText((Join-Path $fixture 'script/test/test_report.ps1'),$publisherStub)
[IO.File]::WriteAllText((Join-Path $fixture 'script/report/portal.ps1'),'# fixture: no remote operations')
[IO.File]::WriteAllText((Join-Path $fixture 'public/summary.json'),'{}')
$priorExpected=$env:WINDOWS_SETUP_BINDING_EXPECTED;$priorPreference=$ErrorActionPreference
$results=@()
Push-Location (Join-Path $fixture 'unrelated')
try{
 foreach($entry in @('stage','publish')){
  foreach($mode in @('default','explicit')){
   $env:WINDOWS_SETUP_BINDING_EXPECTED=Join-Path $fixture $(if($mode -eq 'default'){'script/release/driver_release_assets.json'}else{'custom metadata [literal].json'})
   if($entry -eq 'stage'){
    $path=Join-Path $fixture 'script/release/stage_driver_release.ps1'
    $arguments=@('-Version','v1.2.3','-Repository','fixture/repo','-AssetDirectory',(Join-Path $fixture 'public'))
    if($mode -eq 'explicit'){$arguments+=@('-MetadataPath',$env:WINDOWS_SETUP_BINDING_EXPECTED)}
   }else{
    $path=Join-Path $fixture 'script/report/publish_quality_release.ps1'
    $arguments=@('-Version','v1.2.3','-Repository','fixture/repo','-PublicDirectory',(Join-Path $fixture 'public'),'-Commit',('a'*40),'-NotesPath',(Join-Path $fixture 'notes.md'))
    if($mode -eq 'explicit'){$arguments+=@('-DriverAssetManifestPath',$env:WINDOWS_SETUP_BINDING_EXPECTED)}
   }
   $log=Join-Path $fixture ($entry+'_'+$mode+'.private.log')
   $ErrorActionPreference='Continue'
   & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path @arguments > $log 2>&1
   $exitCode=$LASTEXITCODE;$ErrorActionPreference='Stop'
   $matched=@(Get-Content -LiteralPath $log|Where-Object {$_ -ceq 'FIXTURE_METADATA_BINDING_MATCH'}).Count -eq 1
   $result=[pscustomobject]@{Entry=$entry;Mode=$mode;ExitCode=$exitCode;Matched=$matched};$results+=@($result)
   Write-Host ('@@BINDING@@'+($result|ConvertTo-Json -Compress))
  }
 }
}finally{$ErrorActionPreference=$priorPreference;$env:WINDOWS_SETUP_BINDING_EXPECTED=$priorExpected;Pop-Location}
foreach($result in $results){Assert ($result.ExitCode -eq 0 -and $result.Matched) ('native PS5.1 '+$result.Entry+' '+$result.Mode+' metadata binding does not depend on caller working directory')}
$global:LASTEXITCODE=0
