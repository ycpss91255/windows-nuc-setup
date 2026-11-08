#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$collector=Join-Path $root 'script/test/powershell_coverage.ps1'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('ps engines 中文 '+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
[IO.File]::WriteAllText((Join-Path $fixture 'branch.ps1'),"function Pick([bool]`$Value) { if(`$Value){return 'yes'}else{return 'no'} }",[Text.UTF8Encoding]::new($true))
[IO.File]::WriteAllText((Join-Path $fixture 'never.ps1'),"function Never { return 'unused' }",[Text.UTF8Encoding]::new($true))
foreach($major in @(5,7)){$choice=if($major -eq 5){'$true'}else{'$false'};$expected=if($major -eq 5){'yes'}else{'no'};$test="BeforeAll { . (Join-Path `$PSScriptRoot 'branch.ps1') }; Describe 'engine $major' { It 'uses requested engine' { `$PSVersionTable.PSVersion.Major | Should-Be $major; Pick $choice | Should-Be '$expected' } }";[IO.File]::WriteAllText((Join-Path $fixture ($major.ToString()+'.Tests.ps1')),$test,[Text.UTF8Encoding]::new($true))}
$manifest=@{SourceRoot=$fixture;Sources=@('branch.ps1','never.ps1');Tests=@('5.Tests.ps1','7.Tests.ps1');TestEngines=@{'7.Tests.ps1'='pwsh'}}
$manifestPath=Join-Path $fixture 'manifest.json';$manifest|ConvertTo-Json -Depth 4|Set-Content $manifestPath -Encoding UTF8
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $collector -ManifestPath $manifestPath -OutputDirectory (Join-Path $fixture 'good') *> (Join-Path $fixture 'good.log')
Assert ($LASTEXITCODE -eq 0) ('依suite選擇5.1與pwsh真子程序 '+$fixture)
$e=Get-Content (Join-Path $fixture 'good/evidence.json') -Raw|ConvertFrom-Json
Assert ($e.Workers.Count -eq 2 -and $e.Workers[0].EngineVersion -like '5.1.*' -and [version]$e.Workers[1].EngineVersion -ge [version]'7.4') '兩個worker記錄實際引擎版本'
Assert (@($e.Workers|Where-Object {$_.EngineSHA256 -notmatch '^[a-f0-9]{64}$'}).Count -eq 0) '記錄實際引擎執行檔SHA256'
Assert ($e.Workers[0].ProcessId -ne $e.Workers[1].ProcessId) '兩引擎程序獨立'
[xml]$xml=Get-Content (Join-Path $fixture 'good/coverage.xml')
$branch=$xml.coverage.packages.package.classes.class|Where-Object filename -eq 'branch.ps1'
Assert (@($branch.lines.line|Where-Object hits -eq 1).Count -eq 1) '跨引擎完整counter union後同一行互補命中'
$never=$xml.coverage.packages.package.classes.class|Where-Object filename -eq 'never.ps1'
Assert ($never.lines.line.hits -eq 0) '未執行來源仍留在完整分母'
foreach($case in @('bad_engine','unknown_suite','missing_pwsh','wrong_pwsh','mapping_array')){
 $bad=@{SourceRoot=$fixture;Sources=@('branch.ps1','never.ps1');Tests=@('5.Tests.ps1');TestEngines=@{}}
 $extra=@()
 switch($case){mapping_array{$bad.TestEngines=@('pwsh')} wrong_pwsh{$bad.Tests=@('7.Tests.ps1');$bad.TestEngines['7.Tests.ps1']='pwsh';$extra=@('-PwshPath',(Join-Path $PSHOME 'powershell.exe'))} bad_engine{$bad.TestEngines['5.Tests.ps1']='unsupported'} unknown_suite{$bad.TestEngines['absent.Tests.ps1']='pwsh'} missing_pwsh{$bad.Tests=@('7.Tests.ps1');$bad.TestEngines['7.Tests.ps1']='pwsh';$extra=@('-PwshPath',(Join-Path $fixture 'missing/pwsh.exe'))}}
 $path=Join-Path $fixture ($case+'.json');$bad|ConvertTo-Json -Depth 4|Set-Content $path -Encoding UTF8
 $ErrorActionPreference='Continue'; & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $collector -ManifestPath $path -OutputDirectory (Join-Path $fixture $case) @extra *> (Join-Path $fixture ($case+'.log'));$code=$LASTEXITCODE;$ErrorActionPreference='Stop'
 Assert ($code -ne 0 -and -not(Test-Path (Join-Path $fixture ($case+'/coverage.xml')))) ('不完整引擎設定拒絕，不退回5.1 '+$case)
}
$explicit=Join-Path $fixture 'explicit'
$pwsh=(Get-Command pwsh.exe -CommandType Application|Select-Object -First 1).Source
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $collector -ManifestPath $manifestPath -OutputDirectory $explicit -PwshPath $pwsh *> (Join-Path $fixture 'explicit.log')
Assert ($LASTEXITCODE -eq 0) '可明確指定已預備的pwsh路徑'
$explicitEvidence=Get-Content (Join-Path $explicit 'evidence.json') -Raw|ConvertFrom-Json
Assert ($explicitEvidence.Workers[1].EngineSHA256 -ceq (Get-FileHash -LiteralPath $pwsh -Algorithm SHA256).Hash.ToLowerInvariant()) '顯式引擎雜湊來自實際檔案'
$baseline=Join-Path $fixture 'baseline.json'
& (Join-Path $root 'test/powershell/coverage/create_baseline_manifest.ps1') -SourceRoot $root -OutputPath $baseline
$generated=Get-Content $baseline -Raw|ConvertFrom-Json
Assert ($generated.TestEngines.'test/powershell/integration/managed_catalog_tests.ps1' -eq 'pwsh') '正式基線將.NET8 metadata原檔測試交給pwsh直接量測'
Write-Host 'ALL PASS: true cross-engine counter tests'
