param([switch]$VerifyOnly)
if(-not $VerifyOnly -or -not $PSScriptRoot.StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){throw 'SAFE_MDNS_VERIFYONLY_BOUNDARY'}
$global:MdnsVerificationCalls++
$mode=$global:MdnsVerificationFixture
if($mode -eq 'Throw'){throw 'fixture fresh publisher failure'}
if($mode -eq 'Missing'){return}
$result=[pscustomobject]@{Success=$true;Status='Registered';Name=([Environment]::MachineName+'.local');RunId=[guid]::NewGuid().ToString('D');RemoteVerified=$false;Detail='fixture publisher status'}
switch($mode){'False'{$result.Success=$false};'StringTrue'{$result.Success='true'};'WrongName'{$result.Name='another-device.local'};'WrongStatus'{$result.Status='LocalMatched'};'BadRunId'{$result.RunId='old-unknown'};'RemoteTrue'{$result.RemoteVerified=$true};'Duplicate'{$result}}
$result