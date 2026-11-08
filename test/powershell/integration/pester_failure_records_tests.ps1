#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$collector=Join-Path $root 'script/test/powershell_coverage.ps1'
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
$fixture=Join-Path $env:TEMP ('pester_failure_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
function Put([string]$Name,[string]$Text){[IO.File]::WriteAllText((Join-Path $fixture $Name),$Text,[Text.UTF8Encoding]::new($true))}
Put 'source.ps1' 'function Example {return 1}'
$cases=@(
 @{Name='discovery';Phase='ContainerDiscovery';Text="throw 'PRIVATE-PESTER-FAILURE-SENTINEL'"},
 @{Name='block';Phase='BlockSetup';Text="Describe 'block' {BeforeAll {throw 'PRIVATE-PESTER-FAILURE-SENTINEL'};It 'not reached' {1|Should-Be 1}}"},
 @{Name='teardown';Phase='BlockLifecycle';Text="Describe 'block teardown' {It 'actually passes' {Write-Host '@@ASSERT@@{`"Name`":`"owned teardown fixture executed`",`"Passed`":true}';1|Should-Be 1};AfterAll {throw 'PRIVATE-PESTER-FAILURE-SENTINEL'}}"},
 @{Name='test';Phase='TestRun';Text="Describe 'test' {It 'fails' {throw 'PRIVATE-PESTER-FAILURE-SENTINEL'}}"},
 @{Name='parse';Phase='ContainerDiscovery';Text="Describe 'PRIVATE-PESTER-FAILURE-SENTINEL' {It 'broken' {"}
)
foreach($case in $cases){
 $suite=$case.Name+'.Tests.ps1';Put $suite ($case.Text.Replace('PRIVATE-PESTER-FAILURE-SENTINEL','PRIVATE-PESTER-FAILURE-SENTINEL C:\private\secret.txt'))
 $manifest=Join-Path $fixture ($case.Name+'.manifest.json')
 @{SourceRoot=$fixture;Sources=@('source.ps1');Tests=@($suite)}|ConvertTo-Json|Set-Content -LiteralPath $manifest -Encoding UTF8
 $output=Join-Path $fixture $case.Name;$log=Join-Path $fixture ($case.Name+'.private.log')
 $prior=$ErrorActionPreference;try{$ErrorActionPreference='Continue';& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $collector -ManifestPath $manifest -OutputDirectory $output *> $log;$code=$LASTEXITCODE}finally{$ErrorActionPreference=$prior}
 Assert ($code -ne 0 -and -not(Test-Path -LiteralPath (Join-Path $output 'evidence.json'))) ($case.Name+' 真正Pester失敗保留非零且無完整證據')
 $sidecar=Join-Path $output 'worker_0.private.failure.json'
 Assert (Test-Path -LiteralPath $sidecar) ($case.Name+' 原始Pester ErrorRecord必須保存限型別階段，不只collector通用錯誤')
 $record=Get-Content -LiteralPath $sidecar -Raw -Encoding UTF8|ConvertFrom-Json
 Assert (@($record.Failures|Where-Object Phase -ceq $case.Phase).Count -gt 0) ($case.Name+' 階段來自真正Pester結果')
 Assert (@($record.Failures|Where-Object {$_.File -ceq $suite -and $_.Line -gt 0}).Count -gt 0) ($case.Name+' 原生例外定位到允許相對來源行')
 if($case.Name -eq 'parse'){Assert (@($record.Failures|Where-Object Type -eq 'ParseException').Count -gt 0) '真實parse例外型別保留，不從message猜階段'}
 $text=[IO.File]::ReadAllText($log);$safe=[IO.File]::ReadAllText($sidecar)
 Assert (-not($text.Contains('PRIVATE-PESTER-FAILURE-SENTINEL') -or $safe.Contains('PRIVATE-PESTER-FAILURE-SENTINEL') -or $text.Contains('C:\private\secret.txt') -or $safe.Contains('C:\private\secret.txt') -or $safe.Contains($fixture))) ($case.Name+' manager與sidecar均不洩漏訊息或私有路徑')
 $marker=@(Get-Content -LiteralPath $log|Where-Object {$_ -like '*PowerShell worker failure diagnostic: *'})
 Assert ($marker.Count -eq 1 -and $marker[0].Contains('PesterFailures')) ($case.Name+' parent只轉出通過schema驗證的typed診斷')
}
Put 'null.Tests.ps1' @'
Describe 'real pinned Pester finalize failure' {
 It 'executes the real test before the coverage plugin cannot write its file' {
  Write-Host '@@ASSERT@@{"Name":"owned fixture executed","Passed":true}'
  [void][IO.Directory]::CreateDirectory((Join-Path $PSScriptRoot 'null/worker_0.xml'))
  1|Should-Be 1
 }
}
'@
$manifest=Join-Path $fixture 'null.manifest.json';@{SourceRoot=$fixture;Sources=@('source.ps1');Tests=@('null.Tests.ps1')}|ConvertTo-Json|Set-Content -LiteralPath $manifest -Encoding UTF8
$output=Join-Path $fixture 'null';$log=Join-Path $fixture 'null.private.log'
$prior=$ErrorActionPreference;try{$ErrorActionPreference='Continue';& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $collector -ManifestPath $manifest -OutputDirectory $output *> $log;$code=$LASTEXITCODE}finally{$ErrorActionPreference=$prior}
Assert ($code -ne 0 -and -not(Test-Path -LiteralPath (Join-Path $output 'evidence.json'))) '真實pinnedPester finalize回傳null仍保留失敗與noComplete'
$sidecar=Join-Path $output 'worker_0.private.failure.json'
Assert (Test-Path -LiteralPath $sidecar) '真實InvokePester null-result必須有明確typed診斷'
$record=Get-Content -LiteralPath $sidecar -Raw|ConvertFrom-Json
Assert (@($record.Failures|Where-Object Phase -ceq 'InvokePesterNoResult').Count -gt 0) 'null回傳如實標記，不猜Instrumentation或套用舊ErrorRecord'
$marker=@(Get-Content -LiteralPath $log|Where-Object {$_ -like '*PowerShell worker failure diagnostic: *'})
$observed=$marker[0].Substring($marker[0].IndexOf('diagnostic: ')+12)|ConvertFrom-Json
Assert ($observed.CompletedAssertions -eq 1 -and $observed.FailedAssertionIndices.Count -eq 0) '真Pester test確實執行1個成功斷言後才null，不誤稱測試斷言失敗'
Assert (-not([IO.File]::ReadAllText($sidecar).Contains($fixture))) 'null-result仍只保存允許相對來源，私有plugin路徑不輸出'
Put 'passed.Tests.ps1' "Describe 'passed' {It 'passes' {1|Should-Be 1}}"
Put 'other.Tests.ps1' "Describe 'other' {It 'passes' {1|Should-Be 1}}"
$manifest=Join-Path $fixture 'passed.manifest.json';@{SourceRoot=$fixture;Sources=@('source.ps1');Tests=@('passed.Tests.ps1','other.Tests.ps1')}|ConvertTo-Json|Set-Content -LiteralPath $manifest -Encoding UTF8
$output=Join-Path $fixture 'passed';$log=Join-Path $fixture 'passed.private.log'
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $collector -ManifestPath $manifest -OutputDirectory $output -ThrottleLimit 2 *> $log
Assert ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath (Join-Path $output 'evidence.json'))) '兩個真正常native worker仍產完整原始證據'
Assert (@(Get-ChildItem -LiteralPath $output -Filter '*.private.failure.json').Count -eq 0 -and -not([IO.File]::ReadAllText($log).Contains('PesterFailures'))) '正常量測不新增模擬failure sidecar或失敗診斷'
Write-Host 'ALL PASS: real Pester failure records, no private messages or paths.'
