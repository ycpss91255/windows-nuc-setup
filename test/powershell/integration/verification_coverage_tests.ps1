#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('verification_coverage_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
$manifest=@{SourceRoot=$root;Sources=@('core/verification_library.ps1','core/verification.ps1');Tests=@('test/powershell/unit/verification_helpers_tests.ps1','test/powershell/integration/driver_fresh_wiring_tests.ps1');Wrapper='test/powershell/coverage/safe_suite.ps1'}
$path=Join-Path $fixture 'manifest.json';$manifest|ConvertTo-Json -Depth 5|Set-Content $path -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'script/test/powershell_coverage.ps1') -ManifestPath $path -OutputDirectory (Join-Path $fixture 'output') *> (Join-Path $fixture 'private.log')
Assert ($LASTEXITCODE -eq 0) ('總驗收原檔安全量測成功 '+$fixture)
$e=Get-Content (Join-Path $fixture 'output/evidence.json') -Raw|ConvertFrom-Json
Assert ($e.Sources.Count -eq 2 -and $e.Total -gt 0 -and $e.Covered*100 -ge $e.Total*80) ('總驗收及FreshVerification真原始完整行至少80%：'+$e.Covered+'/'+$e.Total)
