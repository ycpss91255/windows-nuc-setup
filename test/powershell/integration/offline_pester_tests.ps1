#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$fixture=Join-Path $env:TEMP ('offline_pester_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
$package=if($env:WINDOWS_SETUP_PESTER_PACKAGE_PATH){$env:WINDOWS_SETUP_PESTER_PACKAGE_PATH}else{Join-Path $env:TEMP 'windows_setup_pester_6_0_0/pester.zip'}
if(-not(Test-Path -LiteralPath $package -PathType Leaf)){$package=Join-Path $fixture 'official.zip';Invoke-WebRequest -Uri 'https://www.powershellgallery.com/api/v2/package/Pester/6.0.0' -OutFile $package -UseBasicParsing}
$sha='AHIAm7QW11As3sjMayo1rPU4JVIEfBL+ZILAyTyDnMPxMwLFQ3VeAA0prFTx+Y4DgZCUnH2N4+Xb0HDQua2EKA=='
Assert ([Convert]::ToBase64String([Security.Cryptography.SHA512]::Create().ComputeHash([IO.File]::ReadAllBytes($package))) -ceq $sha) 'fixture uses exact official pinned Pester bytes'
$injected=Join-Path $fixture 'official.zip';if($package -ine $injected){Copy-Item -LiteralPath $package -Destination $injected}
[IO.File]::WriteAllText((Join-Path $fixture 'branch.ps1'),"function Pick { return 'yes' }",[Text.UTF8Encoding]::new($true))
[IO.File]::WriteAllText((Join-Path $fixture 'tiny.Tests.ps1'),"BeforeAll { . (Join-Path `$PSScriptRoot 'branch.ps1') }; Describe 'offline source' { It 'runs actual source' { Pick | Should-Be 'yes' } }",[Text.UTF8Encoding]::new($true))
$manifest=Join-Path $fixture 'manifest.json';@{SourceRoot=$fixture;Sources=@('branch.ps1');Tests=@('tiny.Tests.ps1')}|ConvertTo-Json|Set-Content -LiteralPath $manifest -Encoding UTF8
$runner=Join-Path $fixture 'runner.ps1'
@'
param($Collector,$Manifest,$Output,$Package,$TempRoot)
$ErrorActionPreference='Stop'
$env:TEMP=$TempRoot;$env:TMP=$TempRoot;$env:WINDOWS_SETUP_PESTER_PACKAGE_PATH=$Package
function Invoke-WebRequest { throw 'OFFLINE_NETWORK_FORBIDDEN' }
& $Collector -ManifestPath $Manifest -OutputDirectory $Output
'@|Set-Content -LiteralPath $runner -Encoding UTF8
$collector=Join-Path $root 'script/test/powershell_coverage.ps1';$temporary=Join-Path $fixture 'fresh_temp';[void][IO.Directory]::CreateDirectory($temporary)
$log=Join-Path $fixture 'offline.log';$output=Join-Path $fixture 'output'
$old=$ErrorActionPreference;$ErrorActionPreference='Continue'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner $collector $manifest $output $injected $temporary *> $log
$code=$LASTEXITCODE;$ErrorActionPreference=$old
Assert ($code -eq 0) ('real collector must use injected package with network forbidden: '+$fixture)
$e=Get-Content -LiteralPath (Join-Path $output 'evidence.json') -Raw|ConvertFrom-Json
Assert ($e.PesterVersion -ceq '6.0.0' -and $e.Covered -eq 1 -and $e.Total -eq 1) 'offline package runs real Pester and original-source coverage'
Assert (@(Get-ChildItem -LiteralPath (Join-Path $temporary 'windows_setup_pester_6_0_0') -Directory).Count -eq 1) 'module expands only in current user writable temporary cache'
Assert ([Convert]::ToBase64String([Security.Cryptography.SHA512]::Create().ComputeHash([IO.File]::ReadAllBytes($injected))) -ceq $sha) 'injected immutable package bytes remain unchanged'
$bad=Join-Path $fixture 'corrupt.zip';[IO.File]::WriteAllText($bad,'corrupt')
foreach($case in @(@('bad',$bad),@('missing',(Join-Path $fixture 'absent.zip')))){
 $out=Join-Path $fixture $case[0];$log=Join-Path $fixture ($case[0]+'.log')
 $old=$ErrorActionPreference;$ErrorActionPreference='Continue'
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner $collector $manifest $out $case[1] $temporary *> $log
 $code=$LASTEXITCODE;$ErrorActionPreference=$old
 Assert ($code -ne 0 -and -not(Test-Path (Join-Path $out 'evidence.json'))) ('explicit '+$case[0]+' package fails even when valid user cache exists')
 Assert (-not([IO.File]::ReadAllText($log).Contains('OFFLINE_NETWORK_FORBIDDEN'))) 'invalid explicit package never falls back to network'
}
. (Join-Path $root 'script/docker/install_managed_tools.ps1')
$artifact=Get-ContainerPesterArtifact
Assert ($artifact.Version -ceq '6.0.0' -and $artifact.Uri -ceq 'https://www.powershellgallery.com/api/v2/package/Pester/6.0.0' -and $artifact.Algorithm -ceq 'SHA512' -and $artifact.Hash -ceq $sha -and $artifact.HashFormat -ceq 'Base64' -and $artifact.Kind -ceq 'File') 'Docker build pins exact official Pester artifact before offline runtime'
$docker=[IO.File]::ReadAllText((Join-Path $root 'dockerfile/windows_tests.dockerfile'))
Assert ($docker.Contains('WINDOWS_SETUP_PESTER_PACKAGE_PATH="C:/tools/cache/pester.6.0.0.zip"') -and $docker.Contains('USER ContainerUser')) 'nonadministrator container receives fixed package path without host cache'
