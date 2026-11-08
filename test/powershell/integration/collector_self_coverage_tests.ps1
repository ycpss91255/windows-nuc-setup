#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('collector_self_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
$manifest=@{SourceRoot=$root;Sources=@('script/test/powershell_coverage.ps1');Tests=@('test/powershell/integration/powershell_coverage_tests.ps1');Wrapper='test/powershell/coverage/safe_suite.ps1'}
$path=Join-Path $fixture 'manifest.json';$manifest|ConvertTo-Json -Depth 5|Set-Content $path -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'script/test/powershell_coverage.ps1') -ManifestPath $path -OutputDirectory (Join-Path $fixture 'output') *> (Join-Path $fixture 'private.log')
Assert ($LASTEXITCODE -eq 0) ('收集器成功案例隔離收集完成 '+$fixture)
$e=Get-Content (Join-Path $fixture 'output/evidence.json') -Raw|ConvertFrom-Json
[xml]$xml=Get-Content (Join-Path $fixture 'output/coverage.xml')
$saveLine=(Select-String -LiteralPath (Join-Path $root 'script/test/powershell_coverage.ps1') -SimpleMatch '$xml.Save(').LineNumber
$line=@($xml.coverage.packages.package.classes.class.lines.line|Where-Object number -eq $saveLine)
Assert ($line.Count -eq 1 -and [int]$line[0].hits -eq 1) '成功案例確實執行原始collector管理程序直到輸出XML'
Write-Host ('Collector原始管理程序完整行：'+$e.Covered+'/'+$e.Total+'；子worker不冒稱已在同程序量測。')
