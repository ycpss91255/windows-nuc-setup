#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('network_coverage_'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($fixture)
$tests=@('test/powershell/integration/hosts_sync_tests.ps1','test/powershell/unit/network_helpers_tests.ps1')|Where-Object {Test-Path -LiteralPath (Join-Path $root $_)}
$manifest=[ordered]@{SourceRoot=$root;Sources=@('modules/ssh/custom_hosts_sync/network_sites.ps1','modules/ssh/custom_hosts_sync/sync_custom_hosts.ps1');Tests=@($tests);Wrapper='test/powershell/coverage/safe_suite.ps1'}
$path=Join-Path $fixture 'manifest.json';[IO.File]::WriteAllText($path,($manifest|ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))
$output=Join-Path $fixture 'output'
$ErrorActionPreference='Continue'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'script/test/powershell_coverage.ps1') -ManifestPath $path -OutputDirectory $output *> (Join-Path $fixture 'private.log')
$exit=$LASTEXITCODE;$ErrorActionPreference='Stop'
Assert ($exit -eq 0) ('SSH helper 原檔量測成功：'+$fixture)
$evidence=Get-Content (Join-Path $output 'evidence.json') -Raw|ConvertFrom-Json
Assert ($evidence.Sources.Count -eq 2 -and $evidence.Total -gt 0) '兩個正式helper完整保留分母'
Assert (($evidence.Covered*100) -ge ($evidence.Total*80)) ('SSH helper 完整命中行至少80%：'+$evidence.Covered+'/'+$evidence.Total)
