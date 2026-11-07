#Requires -Version 5.1
param([string]$ReportDirectory=(Join-Path ([IO.Path]::GetTempPath()) ('NUC-CI-'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$packageRoot=Split-Path $PSScriptRoot -Parent
if($PSVersionTable.PSVersion.Major -ne 5){throw 'CI 必須使用 Windows PowerShell 5.1。'}
New-Item -ItemType Directory -Path $ReportDirectory -Force|Out-Null
$results=New-Object Collections.Generic.List[object]
$scripts=@(Get-ChildItem (Join-Path $packageRoot 'Core') -Filter '*.ps1')+@(Get-ChildItem (Join-Path $packageRoot 'Modules') -Recurse -Filter '*.ps1'|Where-Object FullName -notmatch '[\\/]Win11Debloat[\\/]')+@(Get-ChildItem $PSScriptRoot -Filter '*.ps1')
$parseFailures=@(foreach($file in $scripts){
 $tokens=$null;$errors=$null
 [void][Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
 foreach($error in $errors){$file.Name+': '+$error.Message}
})
$parseFailures|Out-File (Join-Path $ReportDirectory 'syntax.log') -Encoding UTF8
$results.Add([pscustomobject]@{Name='PowerShell 5.1 語法';Passed=($parseFailures.Count -eq 0);ExitCode=[int]($parseFailures.Count -gt 0)})
$cases=@(
 @{Name='Layout';Path=(Join-Path $PSScriptRoot 'Layout.Tests.ps1');Arguments=@('-PackageRoot',$packageRoot,'-SourceOnly')},
 @{Name='Init';Path=(Join-Path $packageRoot 'Modules\Init\Tests\Init.Tests.ps1');Arguments=@()},
 @{Name='InputMethod';Path=(Join-Path $PSScriptRoot 'InputMethod.Tests.ps1');Arguments=@()},
 @{Name='SourceRelease';Path=(Join-Path $PSScriptRoot 'SourceRelease.Tests.ps1');Arguments=@()},
 @{Name='HostsSync';Path=(Join-Path $PSScriptRoot 'HostsSync.Tests.ps1');Arguments=@()}
)
foreach($case in $cases){
 $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$case.Path)+$case.Arguments
 $code=1
 try{
  & (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') @arguments 2>&1 | Out-File (Join-Path $ReportDirectory ($case.Name+'.log')) -Encoding UTF8
  $code=$LASTEXITCODE
 }catch{$_|Out-String|Out-File (Join-Path $ReportDirectory ($case.Name+'.log')) -Append -Encoding UTF8}
 $results.Add([pscustomobject]@{Name=$case.Name;Passed=($code -eq 0);ExitCode=$code})
 Write-Host ($case.Name+': '+$(if($code -eq 0){'PASS'}else{'FAIL'}))
}
$success=@($results|Where-Object {-not $_.Passed}).Count -eq 0
[ordered]@{Success=$success;CheckedAt=(Get-Date).ToString('o');Scope='Source-only isolated tests; not physical NUC validation';Checks=@($results.ToArray())}|ConvertTo-Json -Depth 5|Out-File (Join-Path $ReportDirectory 'summary.json') -Encoding UTF8
$summary=@('# Windows CI 測試結果','','本次只驗證原始碼與隔離邏輯；沒有執行實際 Windows 設定、Sysprep、驅動安裝或重新開機。','','| 測試項目 | 結果 |','| --- | --- |')
foreach($result in $results){$summary+='| '+$result.Name+' | '+$(if($result.Passed){'PASS'}else{'FAIL'})+' |'}
$summary|Out-File (Join-Path $ReportDirectory 'summary.md') -Encoding UTF8
if($env:GITHUB_STEP_SUMMARY){$summary|Out-File $env:GITHUB_STEP_SUMMARY -Append -Encoding UTF8}
if(-not $success){throw 'CI 測試未通過；請查看短期保留的測試報告。'}
Write-Host '所有 CI 測試通過。實機 Reports 與續跑紀錄未讀取或刪除。'
