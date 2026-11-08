#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++}
$verifier=Join-Path $root 'script/test/verify_start_pins_payload.ps1'
Assert (Test-Path -LiteralPath $verifier -PathType Leaf) 'Start pins package has a dedicated native payload verifier'
. $verifier
Assert (@(Get-StartPinsPayloadPaths).Count -eq 7 -and @((Get-StartPinsPayloadPaths)|Where-Object {$_ -match 'HideOobe'}).Count -eq 0) 'Start package whitelist is independent of unchanged OOBE settings'
$reviewedPath=Join-Path $root 'modules/start_menu/assets/payload_baseline.json'
Assert (Test-Path -LiteralPath $reviewedPath -PathType Leaf) 'shipped Start package has an independently reviewed real-payload baseline'
$reviewed=[IO.File]::ReadAllText($reviewedPath)|ConvertFrom-Json
Assert ($reviewed.SchemaVersion -eq 1 -and $reviewed.OnlySetting -ceq 'Policies/Start/ConfigureStartPins={"pinnedList":[]}' -and $reviewed.PackageSHA256 -ceq (Get-FileHash -LiteralPath (Join-Path $root 'modules/start_menu/assets/empty_start.ppkg')).Hash) 'Start baseline binds exact shipped package and sole approved setting'
Assert (@($reviewed.Files).Count -eq 7 -and @($reviewed.Files.Path|Select-Object -Unique).Count -eq 7 -and (($reviewed.Files.Path|Sort-Object) -join '|') -ceq ((Get-StartPinsPayloadPaths|Sort-Object) -join '|') -and @($reviewed.Files|Where-Object {$_.SHA256 -cnotmatch '^[A-F0-9]{64}$'}).Count -eq 0) 'Start baseline binds all seven unique native-observed XML files'
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
# Invoke public script entry in an isolated child; dot-source-only tests cannot detect parameter clobbering.
$cliEvidence=Join-Path $temp 'cli evidence';$cliBaseline=Join-Path $temp 'missing reviewed baseline.json'
$fixture=Join-Path $root 'test/powershell/fixtures/start_payload_cli.ps1';$cliLog=Join-Path $temp 'cli.log'
$savedPreference=$ErrorActionPreference
try{$ErrorActionPreference='Continue';& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fixture -TargetScript $verifier -PackagePath $package -EvidenceDirectory $cliEvidence -BaselinePath $cliBaseline *> $cliLog;$cliExit=$LASTEXITCODE}finally{$ErrorActionPreference=$savedPreference}
Assert ($cliExit -ne 0 -and (Test-Path -LiteralPath (Join-Path $cliEvidence 'evidence.json'))) 'public CLI preserves supplied package evidence and baseline arguments through imports'
$cliData=[IO.File]::ReadAllText((Join-Path $cliEvidence 'evidence.json'))|ConvertFrom-Json
Assert (-not $cliData.Verified -and $cliData.PackageSHA256 -ceq (Get-FileHash -LiteralPath $package).Hash -and $cliData.Files.Count -eq 7 -and [IO.File]::ReadAllText($cliLog) -match 'XML') 'public CLI reaches extraction and missing-baseline rejection with exact package digest'
# Literal -File entry also preserves parameters before safe, pre-native rejection.
$directLog=Join-Path $temp 'direct_file.log';$missingPackage=Join-Path $temp 'missing package.ppkg'
$savedPreference=$ErrorActionPreference
try{$ErrorActionPreference='Continue';& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $verifier -PackagePath $missingPackage -EvidenceDirectory (Join-Path $temp 'direct evidence') -BaselinePath $cliBaseline *> $directLog;$directExit=$LASTEXITCODE}finally{$ErrorActionPreference=$savedPreference}
Assert ($directExit -ne 0 -and [IO.File]::ReadAllText($directLog) -match '設定包不存在或超過') 'literal File invocation retains package argument and rejects missing file before native access'
$oobeEvidence=Join-Path $temp 'oobe cli evidence';$oobeLog=Join-Path $temp 'oobe_cli.log'
$savedPreference=$ErrorActionPreference
try{$ErrorActionPreference='Continue';& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $fixture -TargetScript (Join-Path $root 'script/test/verify_oobe_payload.ps1') -PackagePath $package -EvidenceDirectory $oobeEvidence -BaselinePath $cliBaseline *> $oobeLog;$oobeExit=$LASTEXITCODE}finally{$ErrorActionPreference=$savedPreference}
Assert ($oobeExit -ne 0 -and (Test-Path -LiteralPath (Join-Path $oobeEvidence 'evidence.json'))) 'original OOBE public entry still reaches baseline rejection after safe extraction'
$oobeData=[IO.File]::ReadAllText((Join-Path $oobeEvidence 'evidence.json'))|ConvertFrom-Json
Assert (-not $oobeData.Verified -and $oobeData.Files.Count -eq 7 -and @($oobeData.Files|Where-Object {$_.Path -match 'HideOobe'}).Count -eq 1) 'OOBE public entry retains its original seven-file scope'
Write-Host ('ALL PASS: '+$script:count+' synthetic Start payload contract assertions; no native extraction or installation')