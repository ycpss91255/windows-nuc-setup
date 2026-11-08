#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
function Test-CICliDelegation($Called,[string]$Root,[string]$Output){
 return ($Called.Layer -ceq 'Integration' -and $Called.Output -ceq $Output -and [IO.Path]::GetFullPath([string]$Called.Root).TrimEnd('\','/') -ieq [IO.Path]::GetFullPath($Root).TrimEnd('\','/'))
}
$library=Join-Path $root 'script/test/ci_runner_library.ps1'
Assert (Test-Path -LiteralPath $library) 'CI 提供可由安全來源套件呼叫的具名函式'
. $library
$temp=Join-Path $env:TEMP ('ci_runner_'+[guid]::NewGuid().ToString('N'))
$fixture=Join-Path $temp '來源 空白'
$encoding=[Text.UTF8Encoding]::new($true)
$keys=@('GITHUB_SHA','GITHUB_REF_TYPE','GITHUB_HEAD_REF','GITHUB_REF_NAME','GITHUB_REPOSITORY','GITHUB_RUN_ID','GITHUB_STEP_SUMMARY','WINDOWS_SETUP_TEST_CONTEXT')
$saved=@{};foreach($key in $keys){$saved[$key]=[Environment]::GetEnvironmentVariable($key,'Process');[Environment]::SetEnvironmentVariable($key,$null,'Process')}
function Put([string]$Relative,[string]$Content){$path=Join-Path $fixture $Relative;[void][IO.Directory]::CreateDirectory((Split-Path $path));[IO.File]::WriteAllText($path,$Content,$encoding)}
function Invoke-FixtureGit([string[]]$Arguments){$output=& git.exe -c core.autocrlf=false -C $fixture @Arguments 2>&1;if($LASTEXITCODE -ne 0){throw ($output|Out-String)};return $output}
function Run([string]$Name,[string]$Layer='All',[string]$ExpectedError=''){
 $out=Join-Path $temp $Name;$actual=''
 try{Invoke-SetupCI -PackageRoot $fixture -ReportDirectory $out -Layer $Layer}catch{$actual=$_.Exception.Message}
 if($ExpectedError){Assert ($actual -like ('*'+$ExpectedError+'*')) ($Name+' 拒絕正確原因：'+$actual)}else{Assert (-not $actual) ($Name+' 真實執行成功：'+$actual)}
 $summary=Join-Path $out 'public/summary.json';if(Test-Path $summary){return (Get-Content -LiteralPath $summary -Encoding UTF8 -Raw|ConvertFrom-Json)}
}
try{
 foreach($dir in @('core','modules','script','test/powershell/unit','test/powershell/integration')){[void][IO.Directory]::CreateDirectory((Join-Path $fixture $dir))}
 $pass='Write-Output ''@@ASSERT@@{"Name":"fixture assertion","Passed":true}'''
 Put 'core/safe.ps1' '# safe fixture'
 Put '.version' 'v1.2.3'
 Put 'doc/changelog/changelog.md' "## [Unreleased]`n- 安全測試來源`n## [v1.2.3]`n- 已發布測試來源"
 Put 'test/powershell/unit/first_tests.ps1' $pass
 Put 'test/powershell/integration/layout_tests.ps1' ('param([string]$PackageRoot,[switch]$SourceOnly)' + "`n" + 'if(-not $SourceOnly -or -not (Test-Path (Join-Path $PackageRoot ''.version''))){exit 9}' + "`n" + $pass)
 Invoke-FixtureGit @('init','--quiet')|Out-Null;Invoke-FixtureGit @('add','.')|Out-Null;Invoke-FixtureGit @('-c','user.name=CI Fixture','-c','user.email=fixture@example.invalid','commit','--quiet','-m','fixture')|Out-Null
 $head=(Invoke-FixtureGit @('rev-parse','HEAD')).Trim()
 $r=Run 'clean'
 Assert ($r.Success -and $r.Checks.Count -eq 3 -and $r.Totals.AssertionsExecuted -eq 2) '完整清單含語法與兩層真子程序斷言'
 Assert ($r.Commit -eq $head -and $r.SourceState -eq 'Clean' -and $r.SchemaVersion -eq 2 -and $r.Coverage -eq 'NotMeasured') '實際 Git 身分與現行 schema 不偽造覆蓋率'
 Assert ($r.Changes[0] -eq '安全測試來源' -and $r.Version -eq 'v1.2.3') '分支版本與變更解析'
 Assert (-not $r.Checks[1].PSObject.Properties['Path']) '公開報表不洩漏私有測試路徑'
 $r=Run 'unit' 'Unit';Assert ($r.Checks.Count -eq 2 -and $r.RequestedLayer -eq 'Unit') '指定 Unit 不執行 Integration'
 $env:GITHUB_SHA=$head;$env:GITHUB_REPOSITORY='fixture/project';$env:GITHUB_RUN_ID='123';$env:GITHUB_HEAD_REF='feature/test';$env:WINDOWS_SETUP_TEST_CONTEXT='Windows container';$env:GITHUB_STEP_SUMMARY=Join-Path $temp 'step.md'
 Put 'core/safe.ps1' '# changed fixture'
 $r=Run 'dirty' 'Integration'
 Assert ($r.SourceState -eq 'Dirty' -and $r.RefName -eq 'feature/test' -and $r.RunUrl -eq 'https://github.com/fixture/project/actions/runs/123' -and $r.Environment -like 'Windows container*') '真 dirty 與 CI 來源資訊保留'
 Assert ((Get-Item -LiteralPath $env:GITHUB_STEP_SUMMARY).Length -gt 0) '真 step summary 已寫入'
 foreach($case in @(@{Name='native';Body=$pass+"`nexit 7";Code=7},@{Name='false';Body='Write-Output ''@@ASSERT@@{"Name":"negative","Passed":false}''';Code=1},@{Name='malformed';Body='Write-Output ''@@ASSERT@@{"Name":"bad","Passed":"true"}''';Code=1},@{Name='empty';Body='Write-Output ''no assertions''';Code=1})){
  Put 'test/powershell/unit/first_tests.ps1' $case.Body
  $r=Run $case.Name 'Unit' 'CI 測試未通過'
  Assert (-not $r.Success -and $r.Checks[1].ExitCode -eq $case.Code) ($case.Name+' 真報表不得假成功')
 }
 Put 'test/powershell/unit/first_tests.ps1' $pass
 Put 'core/safe.ps1' 'function {'
 $r=Run 'syntax' 'Unit' 'CI 測試未通過';Assert (-not $r.Checks[0].Passed) '語法失敗仍保留實際結果'
 Put 'core/safe.ps1' '# safe fixture'
 Put 'test/powershell/unit/ignored.ps1' '# invalid suite name'
 $null=Run 'invalid' 'All' 'Invalid or empty test inventory'
 Remove-Item -LiteralPath (Join-Path $fixture 'test/powershell/unit/ignored.ps1')
 # Release metadata is fixture data, backed by a real clean local commit and the real parser.
 Put 'script/release/release.ps1' ([IO.File]::ReadAllText((Join-Path $root 'script/release/release.ps1')))
 Invoke-FixtureGit @('add','.')|Out-Null;Invoke-FixtureGit @('-c','user.name=CI Fixture','-c','user.email=fixture@example.invalid','commit','--quiet','-m','release fixture')|Out-Null
 $env:GITHUB_SHA=(Invoke-FixtureGit @('rev-parse','HEAD')).Trim();$env:GITHUB_REF_TYPE='tag';$env:GITHUB_HEAD_REF=$null;$env:GITHUB_REF_NAME='v1.2.3'
 $r=Run 'release'
 Assert ($r.RefType -eq 'Release' -and $r.RefName -eq 'v1.2.3' -and $r.Changes[0] -eq '已發布測試來源' -and $r.SourceState -eq 'Clean') '真版本章節解析與發布證據條件保留'
 $env:GITHUB_REF_TYPE=$null
 Remove-Item -LiteralPath (Join-Path $fixture '.version')
 $r=Run 'unversioned' 'Unit';Assert ($r.Version -eq 'Unknown' -and $r.SourceState -eq 'Dirty') '缺版本不假設有效版本'
 # The CLI contract is executed using an isolated copy with a harmless named delegate.
 $cli=Join-Path $temp 'cli_來源_😀/script/test';[void][IO.Directory]::CreateDirectory($cli)
 Copy-Item -LiteralPath (Join-Path $root 'script/test/run_ci.ps1') -Destination $cli
 [IO.File]::WriteAllText((Join-Path $cli 'ci_runner_library.ps1'),'function Invoke-SetupCI {param($PackageRoot,$ReportDirectory,$Layer);@{Root=$PackageRoot;Output=$ReportDirectory;Layer=$Layer}|ConvertTo-Json|Set-Content -LiteralPath $ReportDirectory -Encoding UTF8}', $encoding)
 $cliOut=Join-Path $temp 'cli.json'
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $cli 'run_ci.ps1') -Layer Integration -ReportDirectory $cliOut
 Assert ($LASTEXITCODE -eq 0) 'CLI 真子程序委派成功'
 $called=Get-Content -LiteralPath $cliOut -Raw -Encoding UTF8|ConvertFrom-Json
 Assert ($called.Root.Contains('😀')) 'CLI fixture JSON 必須完整保留非 ANSI Unicode 目錄'
 Assert (Test-CICliDelegation $called (Join-Path $temp 'cli_來源_😀') $cliOut) ('CLI 動態套件根與參數完整委派；actualRoot='+$called.Root+';expectedRoot='+(Join-Path $temp 'cli_來源_😀')+';actualOutput='+$called.Output+';expectedOutput='+$cliOut+';actualLayer='+$called.Layer)
 # Exercise real equivalent directory spellings, including actual 8.3 alias when available.
 $aliases=@((Join-Path $temp 'cli_來源_😀\.'),(Join-Path $temp 'cli_來源_😀\'))
 $fso=New-Object -ComObject Scripting.FileSystemObject
 $shortRoot=[string]$fso.GetFolder((Join-Path $temp 'cli_來源_😀')).ShortPath
 if($shortRoot -ine (Join-Path $temp 'cli_來源_😀')){$aliases+=@($shortRoot)}
 foreach($aliasRoot in $aliases){
  $aliasOut=Join-Path $temp 'alias_cli.json'
  & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $aliasRoot 'script/test/run_ci.ps1') -Layer Integration -ReportDirectory $aliasOut
  Assert ($LASTEXITCODE -eq 0) '等價路徑 CLI 真子程序委派成功'
  $aliasCalled=Get-Content -LiteralPath $aliasOut -Raw -Encoding UTF8|ConvertFrom-Json
  Assert (Test-CICliDelegation $aliasCalled $aliasRoot $aliasOut) ('等價路徑 CLI 動態套件根與參數完整委派；actualRoot='+$aliasCalled.Root+';expectedRoot='+$aliasRoot+';actualOutput='+$aliasCalled.Output+';expectedOutput='+$aliasOut+';actualLayer='+$aliasCalled.Layer)
 }
 Assert (-not(Test-CICliDelegation $called (Join-Path $temp 'different_root') $cliOut)) '不同目錄即使存在共同祖先也拒絕'
 Assert (-not(Test-CICliDelegation ([pscustomobject]@{Root=$called.Root;Output=$cliOut;Layer='Unit'}) (Join-Path $temp 'cli_來源_😀') $cliOut)) 'Layer仍須精確Integration'
 Assert (-not(Test-CICliDelegation ([pscustomobject]@{Root=$called.Root;Output=($cliOut+'.wrong');Layer='Integration'}) (Join-Path $temp 'cli_來源_😀') $cliOut)) 'Output仍須精確原參數'
}finally{
 foreach($key in $keys){[Environment]::SetEnvironmentVariable($key,$saved[$key],'Process')}
 # Only this test-created absolute TEMP tree can be removed.
 if($temp.StartsWith([IO.Path]::GetFullPath($env:TEMP),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $temp -Recurse -Force}
}