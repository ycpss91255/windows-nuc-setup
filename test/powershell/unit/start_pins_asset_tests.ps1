#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$library=Join-Path $root 'modules/start_menu/start_pins_asset_library.ps1'
Assert (Test-Path $library) 'Start policy has independently loadable source validation library'
. $library
$xml=Get-StartPinsSourceXml
Assert ($xml -notmatch 'HideOobe|Password|UserName|applyOnce') 'legacy source excludes OOBE credentials and newer applyOnce setting'
[xml]$doc=$xml
$node=$doc.SelectSingleNode('//*[local-name()="ConfigureStartPins"]')
Assert ($node.InnerText -ceq '{"pinnedList":[]}') 'source only requests empty Start pins JSON'
$fixture=Join-Path $env:TEMP ('start_asset_'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory $fixture
[IO.File]::WriteAllText((Join-Path $fixture 'empty_start.xml'),$xml)
[IO.File]::WriteAllBytes((Join-Path $fixture 'empty_start.ppkg'),[byte[]](1,2,3))
$m=New-StartPinsProvenance (Join-Path $fixture 'empty_start.xml') (Join-Path $fixture 'empty_start.ppkg')
$m|ConvertTo-Json -Depth 4|Set-Content (Join-Path $fixture 'provenance.json') -Encoding UTF8
$verified=Assert-StartPinsAssetSource $fixture
Assert ($verified.PackageName -ceq 'windows_setup_empty_start') 'source validation accepts matching fixture without native apply'
[IO.File]::AppendAllText((Join-Path $fixture 'empty_start.ppkg'),'changed')
$failed=$false;try{Assert-StartPinsAssetSource $fixture}catch{$failed=$true}
Assert $failed 'changed package hash is rejected'
