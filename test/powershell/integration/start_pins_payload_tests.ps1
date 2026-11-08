#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++}
$verifier=Join-Path $root 'script/test/verify_start_pins_payload.ps1'
Assert (Test-Path -LiteralPath $verifier -PathType Leaf) 'Start pins package has a dedicated native payload verifier'
. $verifier
Assert (@(Get-StartPinsPayloadPaths).Count -eq 7 -and @((Get-StartPinsPayloadPaths)|Where-Object {$_ -match 'HideOobe'}).Count -eq 0) 'Start package whitelist is independent of unchanged OOBE settings'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('start_payload_test_'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $temp|Out-Null
$package=Join-Path $temp 'synthetic.ppkg';[IO.File]::WriteAllText($package,'synthetic test fixture')
function Read-StartPinsWimPayload {param($PackagePath,$Destination)
 foreach($name in @(Get-StartPinsPayloadPaths)){$p=Join-Path $Destination $name;New-Item -ItemType Directory -Path (Split-Path $p) -Force|Out-Null;[IO.File]::WriteAllText($p,'<fixture xmlns="urn:synthetic">ConfigureStartPins</fixture>')}
}
$first=Join-Path $temp 'first';$failed=$false;try{Invoke-StartPinsPayloadVerification $package $first}catch{$failed=$true}
Assert ($failed -and (Test-Path (Join-Path $first 'evidence.json'))) 'missing independently reviewed baseline blocks verification but retains raw payload'
$data=[IO.File]::ReadAllText((Join-Path $first 'evidence.json'))|ConvertFrom-Json
Assert (-not $data.Verified -and $data.Files.Count -eq 7) 'first extraction never declares unreviewed package verified'
$baseline=[pscustomobject]@{SchemaVersion=1;PackageSHA256=$data.PackageSHA256;OnlySetting='Policies/Start/ConfigureStartPins={"pinnedList":[]}';Files=$data.Files}
$baselinePath=Join-Path $temp 'synthetic_baseline.json';[IO.File]::WriteAllText($baselinePath,($baseline|ConvertTo-Json -Depth 5))
$result=Invoke-StartPinsPayloadVerification $package (Join-Path $temp 'second') $baselinePath
Assert ($result.Verified -and $result.Files.Count -eq 7) 'all seven exact XML digests roots and namespaces must match reviewed baseline'
$baseline.OnlySetting='OOBE/Desktop/HideOobe=True';[IO.File]::WriteAllText($baselinePath,($baseline|ConvertTo-Json -Depth 5));$failed=$false;try{Invoke-StartPinsPayloadVerification $package (Join-Path $temp 'third') $baselinePath}catch{$failed=$true}
Assert $failed 'OOBE baseline cannot authorize a Start pins package'
$baseline.OnlySetting='Policies/Start/ConfigureStartPins={"pinnedList":[]}';$baseline.Files[0].Namespace='urn:wrong';[IO.File]::WriteAllText($baselinePath,($baseline|ConvertTo-Json -Depth 5));$failed=$false;try{Invoke-StartPinsPayloadVerification $package (Join-Path $temp 'fourth') $baselinePath}catch{$failed=$true}
Assert $failed 'XML namespace mismatch blocks payload verification'
function Read-StartPinsWimPayload {param($PackagePath,$Destination) throw 'Unexpected WIM entry: Multivariant/0/Prov/RunTime/actual.provxml'}
$fifth=Join-Path $temp 'fifth';$failed=$false;try{Invoke-StartPinsPayloadVerification $package $fifth}catch{$failed=$true}
$diagnostic=[IO.File]::ReadAllText((Join-Path $fifth 'evidence.json'))|ConvertFrom-Json
Assert ($failed -and -not $diagnostic.Verified -and $diagnostic.UnexpectedEntry -ceq 'Multivariant/0/Prov/RunTime/actual.provxml') 'unknown native archive entry is diagnostic only and never expands whitelist'
Write-Host ('ALL PASS: '+$script:count+' synthetic Start payload contract assertions; no native extraction or installation')