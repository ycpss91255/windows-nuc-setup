#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('driver_source_coverage_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
$manifest=@{SourceRoot=$root;Sources=@('modules/drivers/install_drivers.ps1','modules/drivers/driver_archive_library.ps1');Tests=@('test/powershell/integration/runtime_failures_tests.ps1');Wrapper='test/powershell/coverage/safe_suite.ps1'}
$path=Join-Path $fixture 'manifest.json';$manifest|ConvertTo-Json -Depth 5|Set-Content $path -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'script/test/powershell_coverage.ps1') -ManifestPath $path -OutputDirectory (Join-Path $fixture 'output') *> (Join-Path $fixture 'private.log')
Assert ($LASTEXITCODE -eq 0) ('驅動安全解壓案例隔離收集成功 '+$fixture)
[xml]$xml=Get-Content (Join-Path $fixture 'output/coverage.xml')
$markerLine=(Select-String -LiteralPath (Join-Path $root 'modules/drivers/driver_archive_library.ps1') -SimpleMatch 'Set-Content -LiteralPath $marker').LineNumber
$archiveClass=@($xml.coverage.packages.package.classes.class|Where-Object filename -eq 'modules/drivers/driver_archive_library.ps1')
$line=@($archiveClass.lines.line|Where-Object number -eq $markerLine)
Assert ($line.Count -eq 1 -and [int]$line[0].hits -eq 1) 'TEMP快取案例真正命中交付原始檔的快取完成紀錄'
$e=Get-Content (Join-Path $fixture 'output/evidence.json') -Raw|ConvertFrom-Json
Write-Host ('Driver完整原檔命中行：'+$e.Covered+'/'+$e.Total+'；安裝分支保留在未命中分母。')
