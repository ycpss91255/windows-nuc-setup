#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$fixture=Join-Path $env:TEMP ('driver_full_source_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
$tests=@('unit/driver_plan','unit/driver_cache_cleanup','unit/driver_no_package','integration/driver_profiles','unit/driver_inventory','unit/driver_inventory_scope','unit/driver_native_tool','unit/driver_dependency_manifest','unit/driver_extension','unit/driver_archive_directory','integration/driver_target','integration/driver_package_execution','integration/driver_installation','integration/driver_component','integration/driver_verification','integration/driver_cli_verification','integration/driver_fresh_wiring','integration/driver_scope','integration/driver_extension_install','integration/driver_legacy_execution','integration/runtime_failures')|ForEach-Object {'test/powershell/'+$_+'_tests.ps1'}
$tests+=@('test/powershell/unit/native_extension_schema_tests.ps1')
$manifest=@{SourceRoot=$root;Sources=@('modules/drivers/install_drivers.ps1','modules/drivers/driver_archive_library.ps1','modules/drivers/driver_plan_library.ps1','modules/drivers/driver_installation_library.ps1');Tests=@($tests);Wrapper='test/powershell/coverage/safe_suite.ps1'}
$path=Join-Path $fixture 'manifest.json';$manifest|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $path -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'script/test/powershell_coverage.ps1') -ManifestPath $path -OutputDirectory (Join-Path $fixture 'output') *> (Join-Path $fixture 'private.log')
Assert ($LASTEXITCODE -eq 0) ('driver原始完整counter隔離量測成功 '+$fixture)
$e=Get-Content -LiteralPath (Join-Path $fixture 'output/evidence.json') -Raw|ConvertFrom-Json
Assert ($e.Sources.Count -eq 4 -and $e.Total -gt 0) '薄入口及三份正式來源完整保留分母'
Assert ($e.Covered*100 -ge $e.Total*80) ('driver原檔完整行至少80%：'+$e.Covered+'/'+$e.Total)
