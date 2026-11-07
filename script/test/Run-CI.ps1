#Requires -Version 5.1
param([ValidateSet('All','Unit','Integration')][string]$Layer='All',[string]$ReportDirectory=(Join-Path ([IO.Path]::GetTempPath()) ('NUC-CI-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$packageRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testRoot=Join-Path $packageRoot 'test'
. (Join-Path $PSScriptRoot 'Test-Report.ps1')
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
 foreach($file in @(Get-ChildItem (Join-Path $testRoot ('powershell/'+$kind.ToLowerInvariant())) -Filter '*.Tests.ps1' -File|Sort-Object Name)){
  @{Name=($kind+'.'+$file.BaseName.Replace('.Tests',''));Layer=$kind;Path=$file.FullName;Arguments=$(if($file.Name -eq 'Layout.Tests.ps1'){@('-PackageRoot',$packageRoot,'-SourceOnly')}else{@()})}
 }
})
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
$results.Add([pscustomobject]@{Name='實機設定驗收';Layer='System';Status='NotRun';Executed=$false;Passed=$null;ExitCode=$null})
$results.Add([pscustomobject]@{Name='全新 Windows 初始化至重開機驗收';Layer='System E2E';Status='NotRun';Executed=$false;Passed=$null;ExitCode=$null})
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
$changes=@()
$changelogPath=Join-Path $packageRoot 'doc/changelog/CHANGELOG.md'
if(Test-Path $changelogPath){
 $changelog=[IO.File]::ReadAllText($changelogPath)
 if($refType -eq 'Release'){
  . (Join-Path $packageRoot 'script/release/Release.ps1')
  $section=Get-ReleaseNotes $version $changelog
 }else{$section=([regex]::Match($changelog,'(?ms)^## \[Unreleased\].*?(?=^## \[|\z)')).Value}
 $changes=@($section -split '\r?\n'|Where-Object {$_ -match '^\s*-\s+\S'}|ForEach-Object {$_ -replace '^\s*-\s+',''})
}
$null=Write-TestReports -Version $version -Environment $environment -RefType $refType -RefName $refName -Changes $changes -Commit $commit -SourceState $sourceState -Checks @($results.ToArray()) -OutputDirectory $publicDirectory -Layer $Layer -RunUrl $runUrl
if($env:GITHUB_STEP_SUMMARY){Get-Content (Join-Path $publicDirectory 'summary.md')|Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding UTF8}
if(-not $success){throw 'CI 測試未通過；請查看短期保留的測試報告。'}
Write-Host '所選單元／隔離整合測試通過；System 與完整 E2E 未執行。實機 reports 與續跑紀錄未讀取或刪除。'
