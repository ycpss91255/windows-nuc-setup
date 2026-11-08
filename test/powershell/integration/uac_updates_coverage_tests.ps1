#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$d=Join-Path ([IO.Path]::GetTempPath()) ('uac_update_coverage_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($d)
$manifest=@{SourceRoot=$root;Sources=@('modules/uac/uac_library.ps1','modules/updates/update_progress_library.ps1','modules/updates/update_worker_library.ps1');Tests=@('test/powershell/unit/uac_helpers_tests.ps1','test/powershell/integration/uac_wiring_tests.ps1','test/powershell/unit/update_progress_tests.ps1','test/powershell/unit/update_worker_tests.ps1');Wrapper='test/powershell/coverage/safe_suite.ps1'}
$path=Join-Path $d 'manifest.json';$manifest|ConvertTo-Json -Depth 4|Set-Content $path -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'script/test/powershell_coverage.ps1') -ManifestPath $path -OutputDirectory (Join-Path $d 'output') *> (Join-Path $d 'private.log')
Assert ($LASTEXITCODE -eq 0) ('三個正式來源真counter收集完成 '+$d)
[xml]$xml=Get-Content (Join-Path $d 'output/coverage.xml') -Raw
$classes=@($xml.coverage.packages.package.classes.class)
Assert ($classes.Count -eq 3) '保留三檔完整分母'
foreach($class in $classes){$lines=@($class.lines.line);$hit=@($lines|Where-Object hits -eq '1').Count;Assert ($lines.Count -gt 0 -and $hit*100 -ge $lines.Count*80) ($class.filename+' 原始完整行至少80%：'+$hit+'/'+$lines.Count)}