#Requires -Version 5.1
param([switch]$NativeSelfTest,[switch]$ExportOnly,[string]$PrivateDirectory,[string]$StepOutcome)
# Temporary hosted diagnostic only; not a product command or coverage result.
$ErrorActionPreference='Stop'
function Invoke-AuditDiagnosticNative([string[]]$Arguments,[string]$Stdout,[string]$Stderr){
 $quoted=@($Arguments|ForEach-Object {'"'+$_+'"'})
 $start=[Diagnostics.ProcessStartInfo]::new('powershell.exe',($quoted -join ' '))
 $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.WindowStyle='Hidden';$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
 $process=[Diagnostics.Process]::new();$process.StartInfo=$start
 if(-not $process.Start()){throw 'Diagnostic native process did not start.'}
 $outTask=$process.StandardOutput.ReadToEndAsync();$errTask=$process.StandardError.ReadToEndAsync()
 $timedOut=-not $process.WaitForExit(3300000)
 if($timedOut){$process.Kill();[void]$process.WaitForExit(5000)}
 $exitCode=if($timedOut){124}else{$process.ExitCode}
 if(-not [Threading.Tasks.Task]::WaitAll([Threading.Tasks.Task[]]@($outTask,$errTask),5000)){throw 'Diagnostic output capture exceeded deadline.'}
 [IO.File]::WriteAllText($Stdout,$outTask.Result,[Text.UTF8Encoding]::new($false));[IO.File]::WriteAllText($Stderr,$errTask.Result,[Text.UTF8Encoding]::new($false))
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
if($ExportOnly){
 if($StepOutcome -cne 'failure'){throw 'ExportOnly requires the actual original step failure outcome.'}
 $expected=[IO.Path]::GetFullPath((Join-Path $env:RUNNER_TEMP 'powershell-shard-private')).TrimEnd('\','/')
 if(-not $PrivateDirectory -or [IO.Path]::GetFullPath($PrivateDirectory).TrimEnd('\','/') -ine $expected){throw 'ExportOnly can read only the fixed owned shard-private directory.'}
 $owned=$expected;$item=Get-Item -LiteralPath $owned -Force
 if(-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Owned diagnostic directory is invalid.'}
 $shard=[int]$env:SHARD_INDEX
 if($env:SHARD_INDEX -cnotmatch '^[0-3]$'){throw 'Original shard identity is invalid.'}
 $manifest=$null;$plan=$null
 $canonical=Join-Path $owned 'canonical_manifest.json';$planPath=Join-Path $owned 'plan/privatecollection_manifest.json'
 if(Test-Path -LiteralPath $canonical -PathType Leaf){$manifest=Get-Content -LiteralPath $canonical -Raw -Encoding UTF8|ConvertFrom-Json}
 if(Test-Path -LiteralPath $planPath -PathType Leaf){$plan=Get-Content -LiteralPath $planPath -Raw -Encoding UTF8|ConvertFrom-Json}
 # This separate post-failure step cannot honestly recover a native exit code
 # from its predecessor. Retain its actual outcome and leave the code unknown.
 $exitCode=$null
 $identity=[ordered]@{Commit=$env:GITHUB_SHA;BaseMain='0d1e35266f29eec83067bda9c1ca55f5ce29e642';RunId=$env:GITHUB_RUN_ID;Attempt=$env:GITHUB_RUN_ATTEMPT;Case=$env:SHARD_INDEX;ExportOnly=$true;StepOutcome=$StepOutcome;ExitCode=$null;TimedOut=$null;CanonicalSourceCount=@($manifest.Sources).Count;CanonicalSuiteCount=@($manifest.Tests).Count;ObservedShardSuiteCount=@($plan.Tests).Count;ShardContext=$plan.ShardContext}
 [IO.File]::WriteAllText((Join-Path $owned 'diagnostic.identity.json'),($identity|ConvertTo-Json -Depth 6 -Compress),[Text.UTF8Encoding]::new($false))
}else{
$owned=Join-Path $env:RUNNER_TEMP ('audit-discovery-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($owned)
$canonical=Join-Path $owned 'canonical.json'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'test/powershell/coverage/create_baseline_manifest.ps1') -SourceRoot $source -OutputPath $canonical | Out-Null
if($LASTEXITCODE -ne 0){throw 'Diagnostic manifest preparation failed.'}
$manifest=Get-Content -LiteralPath $canonical -Raw -Encoding UTF8|ConvertFrom-Json
if($manifest.Sources.Count -ne 131 -or $manifest.Tests.Count -ne 216){throw 'Diagnostic baseline differs from the failed main source.'}
$shard=[int]$env:SHARD_INDEX
if($env:SHARD_INDEX -cnotmatch '^[0-3]$' -or $env:DIAGNOSTIC_CASE -cne $env:SHARD_INDEX){throw 'Diagnostic shard identity is invalid.'}
$private=Join-Path $owned 'private';$publicEvidence=Join-Path $owned 'public'
$stdout=Join-Path $owned 'manager.stdout.private.log';$stderr=Join-Path $owned 'manager.stderr.private.log'
$runUrl='https://github.com/'+$env:GITHUB_REPOSITORY+'/actions/runs/'+$env:GITHUB_RUN_ID
# Execute the actual complete official shard command, including its Go planner,
# all 54 suites, full context and unchanged two-worker scheduling.
$arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $source 'script/test/powershell_coverage_shard.ps1'),'-SourceRoot',$source,'-OutputDirectory',$publicEvidence,'-PrivateDirectory',$private,'-ShardIndex',$env:SHARD_INDEX,'-ShardCount','4','-Commit',$env:GITHUB_SHA,'-RunUrl',$runUrl,'-RunAttempt',$env:GITHUB_RUN_ATTEMPT)
$observed=Invoke-AuditDiagnosticNative -Arguments $arguments -Stdout $stdout -Stderr $stderr
$timedOut=$observed.TimedOut;$exitCode=$observed.ExitCode
$planPath=Join-Path $private 'plan/privatecollection_manifest.json';$plan=$null
if(Test-Path -LiteralPath $planPath -PathType Leaf){$plan=Get-Content -LiteralPath $planPath -Raw -Encoding UTF8|ConvertFrom-Json}
$identity=[ordered]@{Commit=$env:GITHUB_SHA;BaseMain='0d1e35266f29eec83067bda9c1ca55f5ce29e642';RunId=$env:GITHUB_RUN_ID;Attempt=$env:GITHUB_RUN_ATTEMPT;Case=$env:DIAGNOSTIC_CASE;ExitCode=$exitCode;TimedOut=$timedOut;CanonicalSourceCount=$manifest.Sources.Count;CanonicalSuiteCount=$manifest.Tests.Count;ObservedShardSuiteCount=@($plan.Tests).Count;ShardContext=$plan.ShardContext}
[IO.File]::WriteAllText((Join-Path $owned 'identity.json'),($identity|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
}
# Only this fresh owned output is archived. No environment dump, checkout,
# parent TEMP directories, credentials, or secrets are read into the archive.
Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
$zip=Join-Path $env:RUNNER_TEMP ('audit-discovery-'+[guid]::NewGuid().ToString('N')+'.zip')
$zipStream=[IO.File]::Open($zip,[IO.FileMode]::CreateNew)
$archive=[IO.Compression.ZipArchive]::new($zipStream,[IO.Compression.ZipArchiveMode]::Create)
try{
 $directories=[Collections.Generic.Queue[string]]::new();$directories.Enqueue($owned)
 $files=[Collections.Generic.List[IO.FileInfo]]::new()
 while($directories.Count){
  $directory=Get-Item -LiteralPath $directories.Dequeue() -Force
  if($directory.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Diagnostic directories cannot be reparse points.'}
  foreach($item in @(Get-ChildItem -LiteralPath $directory.FullName -Force)){
   if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Diagnostic evidence cannot traverse a reparse point.'}
   if($item.PSIsContainer){$directories.Enqueue($item.FullName)}else{$files.Add($item)}
  }
 }
 foreach($file in $files){
  # Explicitly exclude the compiled planner executable and anything other than
  # owned textual evidence. Nothing from the checkout or surrounding TEMP.
  if($file.Extension -cnotin @('.json','.xml','.log')){continue}
  if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Diagnostic evidence cannot be a reparse point.'}
  $relative=$file.FullName.Substring($owned.Length+1).Replace('\','/')
  [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file.FullName,$relative,[IO.Compression.CompressionLevel]::Optimal)
 }
}finally{$archive.Dispose();$zipStream.Dispose()}
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
Write-Output ('Diagnostic only: sources=131 full-shard='+$shard+' exit='+$exitCode+' encrypted=true')
if(-not $ExportOnly -and $exitCode -ne 0){exit $exitCode}
