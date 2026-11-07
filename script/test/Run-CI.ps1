#Requires -Version 5.1
param([ValidateSet('All','Unit','Integration')][string]$Layer='All',[string]$ReportDirectory=(Join-Path ([IO.Path]::GetTempPath()) ('NUC-CI-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$packageRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$testRoot=Join-Path $packageRoot 'test'
if($PSVersionTable.PSVersion.Major -ne 5){throw 'CI 必須使用 Windows PowerShell 5.1。'}
New-Item -ItemType Directory -Path $ReportDirectory -Force|Out-Null
$results=New-Object Collections.Generic.List[object]
$scripts=@(Get-ChildItem (Join-Path $packageRoot 'core') -Filter '*.ps1')+@(Get-ChildItem (Join-Path $packageRoot 'modules') -Recurse -Filter '*.ps1'|Where-Object FullName -notmatch '[\\/]Win11Debloat[\\/]')+@(Get-ChildItem $testRoot -Recurse -Filter '*.ps1')+@(Get-ChildItem (Join-Path $packageRoot 'script') -Recurse -Filter '*.ps1')
$parseFailures=@(foreach($file in $scripts){
 $tokens=$null;$errors=$null
 [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
 foreach($error in $errors){$file.Name+': '+$error.Message}
})
$parseFailures|Out-File (Join-Path $ReportDirectory 'syntax.log') -Encoding UTF8
$results.Add([pscustomobject]@{Name='PowerShell 5.1 語法';Layer='Static';Status=$(if($parseFailures.Count){'Failed'}else{'Passed'});Executed=$true;Passed=($parseFailures.Count -eq 0);ExitCode=[int]($parseFailures.Count -gt 0)})
$cases=@(
 @{Name='Integration.Architecture';Layer='Integration';Path=(Join-Path $testRoot 'powershell/integration/Architecture.Tests.ps1');Arguments=@()},
 @{Name='Unit.Init';Layer='Unit';Path=(Join-Path $testRoot 'powershell/unit/Init.Tests.ps1');Arguments=@()},
 @{Name='Unit.InputMethod';Layer='Unit';Path=(Join-Path $testRoot 'powershell/unit/InputMethod.Tests.ps1');Arguments=@()},
 @{Name='Unit.Hardware';Layer='Unit';Path=(Join-Path $testRoot 'powershell/unit/Hardware.Tests.ps1');Arguments=@()},
 @{Name='Integration.Layout';Layer='Integration';Path=(Join-Path $testRoot 'powershell/integration/Layout.Tests.ps1');Arguments=@('-PackageRoot',$packageRoot,'-SourceOnly')},
 @{Name='Integration.Init';Layer='Integration';Path=(Join-Path $testRoot 'powershell/integration/Init.Tests.ps1');Arguments=@()},
 @{Name='Integration.SourceRelease';Layer='Integration';Path=(Join-Path $testRoot 'powershell/integration/SourceRelease.Tests.ps1');Arguments=@()},
 @{Name='Integration.Hardware';Layer='Integration';Path=(Join-Path $testRoot 'powershell/integration/Hardware.Tests.ps1');Arguments=@()},
 @{Name='Integration.HostsSync';Layer='Integration';Path=(Join-Path $testRoot 'powershell/integration/HostsSync.Tests.ps1');Arguments=@()}
)
$cases=@($cases|Where-Object {$Layer -eq 'All' -or $_.Layer -eq $Layer})
foreach($case in $cases){
 $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$case.Path)+$case.Arguments
 $code=1
 $previousPreference=$ErrorActionPreference
 try{
  # Native stderr can contain Git warnings; the child exit code decides failure.
  $ErrorActionPreference='Continue'
  & (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') @arguments 2>&1 | Out-File (Join-Path $ReportDirectory ($case.Name+'.log')) -Encoding UTF8
  $code=$LASTEXITCODE
 }catch{$_|Out-String|Out-File (Join-Path $ReportDirectory ($case.Name+'.log')) -Append -Encoding UTF8}finally{$ErrorActionPreference=$previousPreference}
 $results.Add([pscustomobject]@{Name=$case.Name;Layer=$case.Layer;Status=$(if($code -eq 0){'Passed'}else{'Failed'});Executed=$true;Passed=($code -eq 0);ExitCode=$code})
 Write-Host ($case.Name+': '+$(if($code -eq 0){'PASS'}else{'FAIL'}))
}
$results.Add([pscustomobject]@{Name='實機設定驗收';Layer='System';Status='NotRun';Executed=$false;Passed=$null;ExitCode=$null})
$results.Add([pscustomobject]@{Name='全新 Windows 初始化至重開機驗收';Layer='System E2E';Status='NotRun';Executed=$false;Passed=$null;ExitCode=$null})
$success=@($results|Where-Object {$_.Executed -and -not $_.Passed}).Count -eq 0
[ordered]@{Success=$success;CheckedAt=(Get-Date).ToString('o');RequestedLayer=$Layer;Scope='Unit and isolated integration only; system and E2E are NotRun';Checks=@($results.ToArray())}|ConvertTo-Json -Depth 5|Out-File (Join-Path $ReportDirectory 'summary.json') -Encoding UTF8
$summary=@('# Windows CI 測試結果','','本次只驗證原始碼與隔離邏輯；沒有執行實際 Windows 設定、Sysprep、驅動安裝或重新開機。','','| 層級 | 測試項目 | 狀態 |','| --- | --- | --- |')
foreach($result in $results){$summary+='| '+$result.Layer+' | '+$result.Name+' | '+$result.Status+' |'}
$summary|Out-File (Join-Path $ReportDirectory 'summary.md') -Encoding UTF8
if($env:GITHUB_STEP_SUMMARY){$summary|Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding UTF8}
if(-not $success){throw 'CI 測試未通過；請查看短期保留的測試報告。'}
Write-Host '所選單元／隔離整合測試通過；System 與完整 E2E 未執行。實機 reports 與續跑紀錄未讀取或刪除。'
