#Requires -Version 5.1
function Invoke-SetupCI {
 param([Parameter(Mandatory=$true)][string]$PackageRoot,[Parameter(Mandatory=$true)][string]$ReportDirectory,[ValidateSet('All','Unit','Integration')][string]$Layer='All')
$ErrorActionPreference='Stop'
$testRoot=Join-Path $packageRoot 'test'
. (Join-Path $PSScriptRoot 'test_report.ps1')
if($PSVersionTable.PSVersion.Major -ne 5){throw 'CI 必須使用 Windows PowerShell 5.1。'}
New-Item -ItemType Directory -Path $ReportDirectory -Force|Out-Null
$results=New-Object Collections.Generic.List[object]
$scripts=@(Get-ChildItem (Join-Path $packageRoot 'core') -Filter '*.ps1')+@(Get-ChildItem (Join-Path $packageRoot 'modules') -Recurse -Filter '*.ps1'|Where-Object FullName -notmatch '[\\/]Win11Debloat[\\/]')+@(Get-ChildItem $testRoot -Recurse -Filter '*.ps1')+@(Get-ChildItem (Join-Path $packageRoot 'script') -Recurse -Filter '*.ps1')
$parseFailures=@(foreach($file in $scripts){
 $tokens=$null;$errors=$null
 [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
 foreach($parseIssue in $errors){$file.Name+': '+$parseIssue.Message}
})
$parseFailures|Out-File (Join-Path $ReportDirectory 'syntax.log') -Encoding UTF8
$results.Add([pscustomobject]@{Name='PowerShell 5.1 語法';Layer='Static';Status=$(if($parseFailures.Count){'Failed'}else{'Passed'});Executed=$true;Passed=($parseFailures.Count -eq 0);ExitCode=[int]($parseFailures.Count -gt 0)})
# The inventory is the roster: every owned unit/integration suite runs once for All.
$cases=@(foreach($kind in @('Unit','Integration')){
 foreach($file in @(Get-ChildItem (Join-Path $testRoot ('powershell/'+$kind.ToLowerInvariant())) -Filter '*_tests.ps1' -File|Sort-Object Name)){
  @{Name=($kind+'.'+$file.BaseName.Replace('_tests',''));Layer=$kind;Path=$file.FullName;Arguments=$(if($file.Name -eq 'layout_tests.ps1'){@('-PackageRoot',$packageRoot,'-SourceOnly')}else{@()})}
 }
})
# Every test file in each layer must participate; naming mistakes must not hide suites.
foreach($kind in @('unit','integration')){
 $all=@(Get-ChildItem (Join-Path $testRoot ('powershell/'+$kind)) -File -Filter '*.ps1')
 if(-not $all.Count -or @($all|Where-Object {$_.Name -cnotmatch '^[a-z0-9_]+_tests\.ps1$'}).Count){throw ('Invalid or empty test inventory: '+$kind)}
 if(@($cases|Where-Object {$_.Layer -eq $kind}).Count -ne $all.Count){throw ('Incomplete test discovery: '+$kind)}
}
$cases=@($cases|Where-Object {$Layer -eq 'All' -or $_.Layer -eq $Layer})
if(-not $cases.Count){throw '沒有符合所選層級的測試，不得回報成功。'}
foreach($case in $cases){
 $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$case.Path)+$case.Arguments
 $code=1
 $timer=[Diagnostics.Stopwatch]::StartNew()
 $previousPreference=$ErrorActionPreference
 try{
  # Native stderr can contain Git warnings; the child exit code decides failure.
  $ErrorActionPreference='Continue'
  & (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') @arguments 2>&1 | Out-File (Join-Path $ReportDirectory ($case.Name+'.log')) -Encoding UTF8
  $code=$LASTEXITCODE
 }catch{$_|Out-String|Out-File (Join-Path $ReportDirectory ($case.Name+'.log')) -Append -Encoding UTF8}finally{$ErrorActionPreference=$previousPreference}
 $timer.Stop()
 $assertions=@()
 foreach($line in @(Get-Content -LiteralPath (Join-Path $ReportDirectory ($case.Name+'.log')))){
  if($line.StartsWith('@@ASSERT@@')){try{$record=$line.Substring(10)|ConvertFrom-Json;if($record.Passed -isnot [bool] -or $record.Name -isnot [string]){throw 'Invalid assertion record'};$assertions+=$record}catch{$code=1}}
 }
 if(-not $assertions.Count -or @($assertions|Where-Object {-not $_.Passed}).Count){$code=1}
 $results.Add([pscustomobject]@{Name=$case.Name;Layer=$case.Layer;Status=$(if($code -eq 0){'Passed'}else{'Failed'});Executed=$true;Passed=($code -eq 0);ExitCode=$code;DurationSeconds=[math]::Round($timer.Elapsed.TotalSeconds,3);Assertions=$assertions})
 Write-Host ($case.Name+': '+$(if($code -eq 0){'PASS'}else{'FAIL'}))
}
$success=@($results|Where-Object {$_.Executed -and -not $_.Passed}).Count -eq 0
$runUrl=if($env:GITHUB_REPOSITORY -and $env:GITHUB_RUN_ID){'https://github.com/'+$env:GITHUB_REPOSITORY+'/actions/runs/'+$env:GITHUB_RUN_ID}else{''}
$publicDirectory=Join-Path $ReportDirectory 'public'
$sourceState='Unknown'
$commit=$env:GITHUB_SHA
if(Get-Command git.exe -ErrorAction SilentlyContinue){
 $head=& git -C $packageRoot rev-parse HEAD 2>$null
 if($LASTEXITCODE -eq 0){if(-not $commit){$commit=$head};$dirty=@(& git -C $packageRoot status --porcelain 2>$null);if($LASTEXITCODE -eq 0){$sourceState=if($dirty.Count){'Dirty'}else{'Clean'}}}
}
$version=if(Test-Path (Join-Path $packageRoot '.version')){([IO.File]::ReadAllText((Join-Path $packageRoot '.version'))).Trim()}else{'Unknown'}
$refType=if($env:GITHUB_REF_TYPE -eq 'tag'){'Release'}else{'Branch'}
$refName=if($env:GITHUB_HEAD_REF){$env:GITHUB_HEAD_REF}elseif($env:GITHUB_REF_NAME){$env:GITHUB_REF_NAME}else{'local'}
$environment='Windows '+[Environment]::OSVersion.Version.ToString()+' / PowerShell '+$PSVersionTable.PSVersion.ToString()
if($env:WINDOWS_SETUP_TEST_CONTEXT -ceq 'Windows container'){$environment='Windows container / '+$environment}
$changes=@()
$changelogPath=Join-Path $packageRoot 'doc/changelog/changelog.md'
if(Test-Path $changelogPath){
 $changelog=[IO.File]::ReadAllText($changelogPath)
 if($refType -eq 'Release'){
  . (Join-Path $packageRoot 'script/release/release.ps1')
  $section=Get-ReleaseNotes $version $changelog
 }else{$section=([regex]::Match($changelog,'(?ms)^## \[Unreleased\].*?(?=^## \[|\z)')).Value}
 $changes=@($section -split '\r?\n'|Where-Object {$_ -match '^\s*-\s+\S'}|ForEach-Object {$_ -replace '^\s*-\s+',''})
}
$null=Write-TestReports -Version $version -Environment $environment -RefType $refType -RefName $refName -Changes $changes -Commit $commit -SourceState $sourceState -Checks @($results.ToArray()) -OutputDirectory $publicDirectory -Layer $Layer -RunUrl $runUrl
if($env:GITHUB_STEP_SUMMARY){Get-Content (Join-Path $publicDirectory 'summary.md') -Encoding UTF8|Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding UTF8}
if(-not $success){throw 'CI 測試未通過；請查看短期保留的測試報告。'}
Write-Host '所選單元與隔離整合測試通過。'
}
