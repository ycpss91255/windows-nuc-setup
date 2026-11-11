#Requires -Version 5.1
param([switch]$NativeSelfTest)
# Temporary hosted diagnostic only; not a product command or coverage result.
$ErrorActionPreference='Stop'
function Invoke-AuditDiagnosticNative([string[]]$Arguments,[string]$Stdout,[string]$Stderr){
 $quoted=@($Arguments|ForEach-Object {'"'+$_+'"'})
 $process=Start-Process -FilePath powershell.exe -ArgumentList $quoted -WindowStyle Hidden -PassThru -RedirectStandardOutput $Stdout -RedirectStandardError $Stderr
 $timedOut=-not $process.WaitForExit(600000)
 if($timedOut){$process.Kill();[void]$process.WaitForExit(5000)}
 $exitCode=if($timedOut){124}else{$process.ExitCode}
 return [pscustomobject]@{ExitCode=$exitCode;TimedOut=$timedOut}
}
if($NativeSelfTest){
 $fixture=Join-Path ([IO.Path]::GetTempPath()) ('audit-native-test-'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
 foreach($expected in @(0,23)){
  $observed=Invoke-AuditDiagnosticNative -Arguments @('-NoProfile','-Command',('exit '+$expected)) -Stdout (Join-Path $fixture ($expected.ToString()+'.stdout')) -Stderr (Join-Path $fixture ($expected.ToString()+'.stderr'))
  if($observed.ExitCode -isnot [int] -or $observed.ExitCode -ne $expected -or $observed.TimedOut){throw ('Native exit contract failed: expected='+$expected+' actual='+$observed.ExitCode)}
 }
 Write-Output 'Native diagnostic exit 0/23 contract passed.'
 return
}
$source=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$owned=Join-Path $env:RUNNER_TEMP ('audit-discovery-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($owned)
$canonical=Join-Path $owned 'canonical.json'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'test/powershell/coverage/create_baseline_manifest.ps1') -SourceRoot $source -OutputPath $canonical | Out-Null
if($LASTEXITCODE -ne 0){throw 'Diagnostic manifest preparation failed.'}
$manifest=Get-Content -LiteralPath $canonical -Raw -Encoding UTF8|ConvertFrom-Json
if($manifest.Sources.Count -ne 131 -or $manifest.Tests.Count -ne 215 -or $manifest.Tests[2] -cne 'test/powershell/integration/audit_runtime_tests.ps1' -or $manifest.Tests[6] -cne 'test/powershell/integration/ci_runner_tests.ps1'){throw 'Diagnostic baseline differs from the failed source.'}
$manifest.Tests=@($manifest.Tests[2],$manifest.Tests[6]);$manifest.TestEngines=[pscustomobject]@{}
$inputPath=Join-Path $owned 'pair.json'
[IO.File]::WriteAllText($inputPath,($manifest|ConvertTo-Json -Depth 7),[Text.UTF8Encoding]::new($false))
$collector=Join-Path $owned 'collector'
$stdout=Join-Path $owned 'manager.stdout.private.log';$stderr=Join-Path $owned 'manager.stderr.private.log'
$arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $source 'script/test/powershell_coverage.ps1'),'-ManifestPath',$inputPath,'-OutputDirectory',$collector,'-ThrottleLimit','2')
$observed=Invoke-AuditDiagnosticNative -Arguments $arguments -Stdout $stdout -Stderr $stderr
$timedOut=$observed.TimedOut;$exitCode=$observed.ExitCode
$identity=[ordered]@{Commit=$env:GITHUB_SHA;RunId=$env:GITHUB_RUN_ID;Attempt=$env:GITHUB_RUN_ATTEMPT;ExitCode=$exitCode;TimedOut=$timedOut;SourceCount=131;SuiteCount=2}
[IO.File]::WriteAllText((Join-Path $owned 'identity.json'),($identity|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
# Only this fresh owned output is archived. No environment dump, checkout,
# parent TEMP directories, credentials, or secrets are read into the archive.
Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip=Join-Path $env:RUNNER_TEMP ('audit-discovery-'+[guid]::NewGuid().ToString('N')+'.zip')
[IO.Compression.ZipFile]::CreateFromDirectory($owned,$zip)
if((Get-Item -LiteralPath $zip).Length -gt 67108864){throw 'Diagnostic archive exceeds 64 MiB.'}
$aes=[Security.Cryptography.Aes]::Create();$aes.KeySize=256;$aes.GenerateKey();$aes.GenerateIV()
$authenticationKey=[byte[]]::new(32);$rng=[Security.Cryptography.RandomNumberGenerator]::Create();$rng.GetBytes($authenticationKey)
$plain=[IO.File]::ReadAllBytes($zip)
$cipher=$aes.CreateEncryptor().TransformFinalBlock($plain,0,$plain.Length)
$macInput=[byte[]]::new($aes.IV.Length+$cipher.Length);[Array]::Copy($aes.IV,0,$macInput,0,$aes.IV.Length);[Array]::Copy($cipher,0,$macInput,$aes.IV.Length,$cipher.Length)
$hmac=[Security.Cryptography.HMACSHA256]::new($authenticationKey);$tag=$hmac.ComputeHash($macInput)
$wrapped=[byte[]]::new(64);[Array]::Copy($aes.Key,0,$wrapped,0,32);[Array]::Copy($authenticationKey,0,$wrapped,32,32)
$rsa=[Security.Cryptography.RSACryptoServiceProvider]::new(3072);$rsa.PersistKeyInCsp=$false;$rsa.FromXmlString([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'audit_discovery_public.xml')))
$envelope=[ordered]@{Algorithm='RSA3072-OAEP-SHA1+AES256-CBC+HMAC-SHA256';WrappedKey=[Convert]::ToBase64String($rsa.Encrypt($wrapped,$true));IV=[Convert]::ToBase64String($aes.IV);Ciphertext=[Convert]::ToBase64String($cipher);Tag=[Convert]::ToBase64String($tag)}
$public=Join-Path $env:RUNNER_TEMP 'audit-discovery-encrypted';[void][IO.Directory]::CreateDirectory($public)
[IO.File]::WriteAllText((Join-Path $public 'diagnostic.encrypted.json'),($envelope|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Write-Output ('Diagnostic only: sources=131 suites=2 exit='+$exitCode+' encrypted=true')
if($exitCode -ne 0){exit $exitCode}
