#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$fixture=$env:WINDOWS_SETUP_BUNDLE_FIXTURE_DIR
if(-not $fixture){
 $fixture=Join-Path $env:TEMP ('publisher_bundle_fixture_'+[guid]::NewGuid().ToString('N'))
 $env:WINDOWS_SETUP_BUNDLE_FIXTURE_DIR=$fixture
 Push-Location $root
 try{& go.exe test -count=1 -run '^TestExportSyntheticConsumerFixture$' ./script/test/report_bundle_tool;if($LASTEXITCODE -ne 0){throw '無法建立合成工件。'}}finally{Pop-Location}
}
$data=Get-Content -LiteralPath (Join-Path $fixture 'fixture.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert ($data.kind -ceq 'Synthetic') '僅使用標明 Synthetic 的受控工件'
$source=Join-Path $fixture $data.source
$fixtureNative=Join-Path $fixture 'windows-test-reports-1-1'
$container=Join-Path $fixture 'docker-test-reports-1-1'
$work=Join-Path $env:TEMP ('publisher_bundle_replay_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work -ErrorAction Stop|Out-Null
$baselineRoot=Join-Path $work 'baseline';New-Item -ItemType Directory -Path $baselineRoot|Out-Null
$native=Join-Path $baselineRoot 'windows-test-reports-1-1'
Copy-Item -LiteralPath $fixtureNative -Destination $native -Recurse
$archive=Join-Path $baselineRoot $data.archive
$bundleTool=Join-Path $work 'report_bundle_tool.exe';$coverageTool=Join-Path $work 'repo_coverage_tool.exe'
Push-Location $root
try{
 & go.exe build -o $bundleTool ./script/test/report_bundle_tool;if($LASTEXITCODE -ne 0){throw '建立封裝驗證工具失敗。'}
 & go.exe build -o $coverageTool ./script/test/repo_coverage_tool;if($LASTEXITCODE -ne 0){throw '建立覆蓋率工具失敗。'}
}finally{Pop-Location}
$identity=@('--source-root',$source,'--version',$data.version,'--commit',$data.commit,'--run-url',$data.run_url,'--run-attempt',[string]$data.run_attempt)
& $bundleTool export --native-dir $native --container-dir $container @identity --output $archive
Assert ($LASTEXITCODE -eq 0) 'PS5 可比較摘要與附件的第一份報告可真實封裝'
$alternateRoot=Join-Path $work 'alternate';New-Item -ItemType Directory -Path $alternateRoot|Out-Null
$alternateNative=Join-Path $alternateRoot 'windows-test-reports-1-1'
Copy-Item -LiteralPath $native -Destination $alternateNative -Recurse
[IO.File]::AppendAllText((Join-Path $alternateNative 'summary.md'),"`n")
$alternateArchive=Join-Path $alternateRoot $data.archive
& $bundleTool export --native-dir $alternateNative --container-dir $container @identity --output $alternateArchive
Assert ($LASTEXITCODE -eq 0) '不同原始 bytes 的同身份第二份報告可真實封裝'
& $bundleTool verify --archive $alternateArchive @identity
Assert ($LASTEXITCODE -eq 0) '同身份第二份封裝通過真實驗證'
Assert ((Get-FileHash -LiteralPath $archive).Hash -cne (Get-FileHash -LiteralPath $alternateArchive).Hash) '兩份合法封裝的 bytes 不同'
$notes=Join-Path $work 'notes.md';[IO.File]::WriteAllText($notes,'synthetic test notes')
$drivers=Join-Path $work 'drivers.json';[IO.File]::WriteAllText($drivers,'{"SchemaVersion":1,"Releases":[]}')
$global:mockCreate=0
function gh {
 $words=@($args);$global:LASTEXITCODE=0
 if($words[0] -ceq 'api' -and $words[1] -like '*/commits/*'){return $data.commit}
 if($words[0] -ceq 'api' -and $words -contains '--paginate'){return}
 if($words[0] -ceq 'release' -and $words[1] -ceq 'create'){$global:mockCreate++;throw 'MOCK_CREATE_AFTER_VERIFICATION'}
 throw ('Unexpected mock gh call: '+($words -join ' '))
}
$arguments=@{PublicDirectory=$alternateNative;ContainerDirectory=$container;Version=$data.version;Commit=$data.commit;NotesPath=$notes;Repository='example/windows_setup';CoverageToolPath=$coverageTool;DriverAssetManifestPath=$drivers;ReportArchive=$archive;BundleToolPath=$bundleTool;RunAttempt=[int]$data.run_attempt;RunUrl=$data.run_url;SourceRoot=$source}
Assert ((Get-Command gh).CommandType -eq 'Function') '使用 mock gh，不執行實際發布'
$caught='';try{& (Join-Path $root 'script/report/publish_quality_release.ps1') @arguments}catch{$caught=$_.Exception.Message}
Write-Host ('Synthetic mismatch result: '+$caught)
Assert ($caught -ceq '封裝與同次原始報表不一致。' -and $global:mockCreate -eq 0) '同身份不同原始 bytes 在建立草稿前拒絕'
$arguments.PublicDirectory=$native
Assert ((Get-Command gh).CommandType -eq 'Function') '正例同樣使用 mock gh'
$caught='';try{& (Join-Path $root 'script/report/publish_quality_release.ps1') @arguments}catch{$caught=$_.Exception.Message}
Assert ($caught -ceq 'MOCK_CREATE_AFTER_VERIFICATION' -and $global:mockCreate -eq 1) '原始 bytes 一致才到達受控建立草稿邊界'
Remove-Item Function:\gh
Write-Host 'ALL PASS: synthetic bundle publication boundary; mocked gh'
