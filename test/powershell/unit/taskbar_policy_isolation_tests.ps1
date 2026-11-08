#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('taskbar_native_guard_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
$runner=Join-Path $fixture 'runner.ps1';$proof=Join-Path $fixture 'proof.json';$log=Join-Path $fixture 'private.log'
$text=@'
param([string]$SourceRoot,[string]$ProofPath)
$ErrorActionPreference='Stop'
# This inert, same-ABI type cannot call Windows. Never execute real AppBar to test isolation.
Add-Type -TypeDefinition 'namespace WindowsSetup { public static class Taskbar { public static int Calls; public static uint AutoHide(bool apply, object unused) { Calls++; throw new System.InvalidOperationException("SAFE_NATIVE_SENTINEL_REACHED"); } } }'
$failure=$null
try{& (Join-Path $SourceRoot 'test/powershell/unit/taskbar_policy_path_tests.ps1')}
catch{$failure=$_}
finally{@{NativeCalls=[WindowsSetup.Taskbar]::Calls}|ConvertTo-Json|Set-Content -LiteralPath $ProofPath -Encoding UTF8}
if($failure){throw $failure}
'@
[IO.File]::WriteAllText($runner,$text,[Text.UTF8Encoding]::new($true))
$prior=$ErrorActionPreference
try{$ErrorActionPreference='Continue';& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner -SourceRoot $root -ProofPath $proof *> $log;$native=$LASTEXITCODE}
finally{$ErrorActionPreference=$prior}
$result=Get-Content -LiteralPath $proof -Raw|ConvertFrom-Json
$originalAssertions=@(Get-Content -LiteralPath $log|Where-Object {$_ -match '^@@ASSERT@@\{'}|ForEach-Object {$_.Substring(10)|ConvertFrom-Json})
$passed=($native -eq 0 -and $result.NativeCalls -eq 0 -and $originalAssertions.Count -ge 5 -and @($originalAssertions|Where-Object {-not $_.Passed}).Count -eq 0)
Write-Host ('@@ASSERT@@'+(@{Name=('組合政策案例保留全部斷言且不得呼叫原生AppBar；nativeExit='+$native+' nativeCalls='+$result.NativeCalls+' policyAssertions='+$originalAssertions.Count);Passed=$passed}|ConvertTo-Json -Compress))
if(-not $passed){throw 'Policy fixture crossed the inert native trap or did not complete its original assertions.'}
