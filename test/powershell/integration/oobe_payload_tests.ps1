#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$scriptPath=Join-Path $root 'script\test\verify_oobe_payload.ps1'
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Name)};$script:count++}
Assert (Test-Path $scriptPath) 'read-only payload verifier exists'
. $scriptPath
$reviewedPath=Join-Path $root 'modules/init/assets/payload_baseline.json'
Assert (Test-Path -LiteralPath $reviewedPath) 'release contains the independently reviewed payload baseline'
$reviewed=[IO.File]::ReadAllText($reviewedPath)|ConvertFrom-Json
Assert ($reviewed.SchemaVersion -eq 1 -and $reviewed.OnlySetting -ceq 'OOBE/Desktop/HideOobe=True' -and $reviewed.PackageSHA256 -ceq (Get-FileHash -LiteralPath (Join-Path $root 'modules/init/assets/hide_oobe.ppkg') -Algorithm SHA256).Hash) 'reviewed baseline binds the exact shipped package'
Assert (@($reviewed.Files).Count -eq 7 -and (($reviewed.Files.Path|Sort-Object) -join '|') -ceq ((Get-OobePayloadPaths|Sort-Object) -join '|') -and @($reviewed.Files|Where-Object {$_.SHA256 -cnotmatch '^[A-F0-9]{64}$'}).Count -eq 0) 'reviewed baseline binds seven unique allowed XML files'
Initialize-OobeWimReader
Assert ([bool]('WindowsSetup.OobeWimReader' -as [type])) 'native adapter compiles without invoking WIM'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('payload_test_'+[guid]::NewGuid().ToString('N'));New-Item -ItemType Directory -Path $temp|Out-Null
$package=Join-Path $temp 'synthetic.ppkg';[IO.File]::WriteAllText($package,'synthetic only')
function Read-OobeWimPayload {param($PackagePath,$Destination)
 foreach($name in @(Get-OobePayloadPaths)){$p=Join-Path $Destination $name;New-Item -ItemType Directory -Path (Split-Path $p) -Force|Out-Null;[IO.File]::WriteAllText($p,'<fixture xmlns="urn:test">HideOobe=True</fixture>')}
}
$evidence=Join-Path $temp 'first'
$failed=$false;try{Invoke-OobePayloadVerification -PackagePath $package -EvidenceDirectory $evidence}catch{$failed=$true}
Assert ($failed -and (Test-Path (Join-Path $evidence 'evidence.json'))) 'missing reviewed baseline fails but retains extracted evidence'
$data=[IO.File]::ReadAllText((Join-Path $evidence 'evidence.json'))|ConvertFrom-Json
$baseline=[pscustomobject]@{SchemaVersion=1;PackageSHA256=$data.PackageSHA256;OnlySetting='OOBE/Desktop/HideOobe=True';Files=$data.Files}
$baselinePath=Join-Path $temp 'synthetic_reviewed_baseline.json';[IO.File]::WriteAllText($baselinePath,($baseline|ConvertTo-Json -Depth 5))
$result=Invoke-OobePayloadVerification $package (Join-Path $temp 'second') $baselinePath
Assert ($result.Verified -and $result.Files.Count -eq 7) 'exact trusted baseline binds all XML contents and package hash'
$baseline.Files[0].Namespace='urn:wrong';[IO.File]::WriteAllText($baselinePath,($baseline|ConvertTo-Json -Depth 5))
$failed=$false;try{Invoke-OobePayloadVerification $package (Join-Path $temp 'third') $baselinePath}catch{$failed=$true}
Assert $failed 'namespace mismatch is rejected'
function Read-OobeWimPayload {param($PackagePath,$Destination)
 foreach($name in @(Get-OobePayloadPaths)){$p=Join-Path $Destination $name;New-Item -ItemType Directory -Path (Split-Path $p) -Force|Out-Null;[IO.File]::WriteAllText($p,'<!DOCTYPE x [<!ENTITY a "bad">]><fixture>&a;</fixture>')}
}
$failed=$false;try{Invoke-OobePayloadVerification $package (Join-Path $temp 'fourth') $baselinePath}catch{$failed=$true}
Assert $failed 'DTD and entity content rejected before baseline acceptance'
function Read-OobeWimPayload {param($PackagePath,$Destination) New-Item -ItemType Directory -Path $Destination -Force|Out-Null;[IO.File]::WriteAllText((Join-Path $Destination 'unexpected.xml'),'<fixture/>')}
$failed=$false;try{Invoke-OobePayloadVerification $package (Join-Path $temp 'fifth') $baselinePath}catch{$failed=$true}
Assert $failed 'unexpected payload file cannot pass'
Write-Host ('ALL PASS: '+$script:count+' mocked extraction assertions; no WIM extraction or elevation')
