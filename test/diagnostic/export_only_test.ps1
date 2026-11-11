#Requires -Version 5.1
$ErrorActionPreference='Stop'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('export-private-test-'+[guid]::NewGuid().ToString('N'))
$tool=Join-Path $fixture 'tool';$runner=Join-Path $fixture 'runner';$owned=Join-Path $runner 'powershell-shard-private'
foreach($dir in @($tool,$runner,$owned,(Join-Path $owned 'plan'),(Join-Path $owned 'collector'))){[void][IO.Directory]::CreateDirectory($dir)}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'audit_discovery.ps1') -Destination (Join-Path $tool 'audit_discovery.ps1')
$rsa=[Security.Cryptography.RSACryptoServiceProvider]::new(3072);$rsa.PersistKeyInCsp=$false
[IO.File]::WriteAllText((Join-Path $tool 'audit_discovery_public.xml'),$rsa.ToXmlString($false))
$marker='PRIVATE_EXPORT_MARKER_'+[guid]::NewGuid().ToString('N')
[IO.File]::WriteAllText((Join-Path $owned 'collector/worker_0.private.error.json'),('{"fixture":"'+$marker+'"}'))
[IO.File]::WriteAllText((Join-Path $owned 'canonical_manifest.json'),'{"Sources":["core/fixture.ps1"],"Tests":["test/fixture.ps1"]}')
[IO.File]::WriteAllText((Join-Path $owned 'plan/privatecollection_manifest.json'),'{"Tests":["test/fixture.ps1"],"ShardContext":{"fixture":true}}')
[IO.File]::WriteAllText((Join-Path $owned 'planner.exe'),'excluded fixture')
[IO.File]::WriteAllText((Join-Path $runner 'other_private.json'),'outside the owned input')
$keys=@('RUNNER_TEMP','SHARD_INDEX','GITHUB_SHA','GITHUB_RUN_ID','GITHUB_RUN_ATTEMPT');$saved=@{}
foreach($key in $keys){$saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process')}
function Assert-Export([bool]$Value,[string]$Name){if(-not $Value){throw $Name};Write-Output ('PASS '+$Name)}
try{
 $env:RUNNER_TEMP=$runner;$env:SHARD_INDEX='3';$env:GITHUB_SHA='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';$env:GITHUB_RUN_ID='123';$env:GITHUB_RUN_ATTEMPT='1'
 $messages=@(& (Join-Path $tool 'audit_discovery.ps1') -ExportOnly -PrivateDirectory $owned -StepOutcome failure)
 Assert-Export (-not ($messages -join '').Contains($marker)) 'ExportOnly never prints private content'
 $envelope=Get-Content -LiteralPath (Join-Path $runner 'audit-discovery-encrypted/diagnostic.encrypted.json') -Raw|ConvertFrom-Json
 $wrapped=$rsa.Decrypt([Convert]::FromBase64String($envelope.WrappedKey),$true)
 $iv=[Convert]::FromBase64String($envelope.IV);$cipher=[Convert]::FromBase64String($envelope.Ciphertext)
 $input=[byte[]]::new($iv.Length+$cipher.Length);[Array]::Copy($iv,0,$input,0,$iv.Length);[Array]::Copy($cipher,0,$input,$iv.Length,$cipher.Length)
 $hmac=[Security.Cryptography.HMACSHA256]::new([byte[]]$wrapped[32..63])
 Assert-Export ([Convert]::ToBase64String($hmac.ComputeHash($input)) -ceq $envelope.Tag) 'MAC validates before any decryption'
 $tampered=[byte[]]$input.Clone();$tampered[20]=$tampered[20] -bxor 1
 Assert-Export ([Convert]::ToBase64String($hmac.ComputeHash($tampered)) -cne $envelope.Tag) 'ciphertext tampering changes the MAC'
 $aes=[Security.Cryptography.Aes]::Create();$aes.Key=[byte[]]$wrapped[0..31];$aes.IV=$iv
 $zip=Join-Path $fixture 'authenticated.zip';[IO.File]::WriteAllBytes($zip,$aes.CreateDecryptor().TransformFinalBlock($cipher,0,$cipher.Length))
 $archive=[IO.Compression.ZipFile]::OpenRead($zip)
 try{
  $names=@($archive.Entries|ForEach-Object FullName)
  Assert-Export ('collector/worker_0.private.error.json' -cin $names -and 'planner.exe' -cnotin $names -and 'other_private.json' -cnotin $names) 'archive contains owned raw evidence but excludes executable and other TEMP files'
  $reader=[IO.StreamReader]::new($archive.GetEntry('diagnostic.identity.json').Open())
  try{$identity=$reader.ReadToEnd()|ConvertFrom-Json}finally{$reader.Dispose()}
  Assert-Export ($identity.ExportOnly -eq $true -and $identity.StepOutcome -ceq 'failure' -and $null -eq $identity.ExitCode) 'separate post-failure step reports its actual outcome and an unknown native code'
  $reader=[IO.StreamReader]::new($archive.GetEntry('collector/worker_0.private.error.json').Open())
  try{$raw=$reader.ReadToEnd()}finally{$reader.Dispose()}
  Assert-Export ($raw.Contains($marker)) 'authenticated archive retains original private evidence'
 }finally{$archive.Dispose()}
 $refused=$false;try{& (Join-Path $tool 'audit_discovery.ps1') -ExportOnly -PrivateDirectory $runner -StepOutcome failure|Out-Null}catch{$refused=$true}
 Assert-Export $refused 'parent TEMP cannot be substituted for the owned private directory'
 $outside=Join-Path $runner 'outside-owned-fixture';[void][IO.Directory]::CreateDirectory($outside)
 [IO.File]::WriteAllText((Join-Path $outside 'outside.json'),'must not be traversed')
 New-Item -ItemType Junction -Path (Join-Path $owned 'outside_link') -Target $outside|Out-Null
 $refused=$false;try{& (Join-Path $tool 'audit_discovery.ps1') -ExportOnly -PrivateDirectory $owned -StepOutcome failure|Out-Null}catch{$refused=$true}
 Assert-Export $refused 'archive refuses a descendant junction outside the owned private directory'
}finally{foreach($key in $keys){[Environment]::SetEnvironmentVariable($key,$saved[$key],'Process')};$rsa.Dispose()}
