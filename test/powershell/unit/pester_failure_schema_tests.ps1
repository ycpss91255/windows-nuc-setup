#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/test/powershell_worker_diagnostics.ps1')
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
Assert ((Get-Command Get-PowerShellWorkerFailureDiagnostic).Parameters.ContainsKey('FailureRecordPath')) 'parent診斷必須提供嚴格typed sidecar入口'
$temp=Join-Path $env:TEMP ('pester_schema_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
$file=Join-Path $temp 'failure.json'
$empty=Join-Path $temp 'empty.log';[IO.File]::WriteAllText($empty,'')
function Read-Record([string]$Text){[IO.File]::WriteAllText($file,$Text,[Text.UTF8Encoding]::new($false));Get-PowerShellWorkerFailureDiagnostic -SourceRoot $temp -TestFile 'suite.ps1' -WorkerIndex 0 -Engine powershell -NativeExitCode 1 -FailureRecordPath $file -AllowedFiles @('suite.ps1') -StandardOutputPath $empty -StandardErrorPath $empty}
$valid='{"SchemaVersion":1,"Failures":[{"Phase":"ContainerDiscovery","Type":"RuntimeException","File":"suite.ps1","Line":1}]}'
$result=Read-Record $valid
Assert ($result.PesterFailures.Count -eq 1 -and $result.PesterFailures[0].Phase -ceq 'ContainerDiscovery') '合法有界sidecar只輸出固定typed欄位'
$cases=@(
 $valid.Replace('"SchemaVersion":1','"SchemaVersion":1,"SchemaVersion":1'),
 $valid.Replace('"Failures":','"PRIVATE":true,"Failures":'),
 $valid.Replace('"Line":1','"Line":"1"'),
 $valid.Replace('"Line":1','"Line":0'),
 $valid.Replace('ContainerDiscovery','PRIVATE'),
 $valid.Replace('RuntimeException','PRIVATE'),
 $valid.Replace('suite.ps1','/private/suite.ps1'),
 $valid.Replace('suite.ps1','../suite.ps1'),
 $valid.Replace('suite.ps1','untracked.ps1'),
 $valid.Replace('"Line":1','"Line":1000001'),
 ('{"SchemaVersion":1,"Failures":['+((@('{"Phase":"TestRun","Type":"Exception","File":"suite.ps1","Line":1}')*17)-join ',')+']}'),
 ('{"SchemaVersion":1,"Failures":['+((@('{"Phase":"TestRun","Type":"Exception","File":"suite.ps1","Line":1}')*2)-join ',')+']}'),
 (' '*32769)
)
$index=0;foreach($text in $cases){$index++;$rejected=$false;try{$null=Read-Record $text}catch{$rejected=$true};Assert $rejected ('拒絕sidecar未知、重複、型別、越界或私有來源 '+$index)}
$thrower=Join-Path $temp 'suite.ps1';[IO.File]::WriteAllText($thrower,"throw 'PRIVATE-MESSAGE C:\private\secret.txt'")
try{& $thrower}catch{$original=$_}
Write-PesterWorkerFailureRecord -Path $file -SourceRoot $temp -AllowedFiles @('suite.ps1') -InvocationErrors @($original)
$produced=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json
Assert ($produced.Failures[0].Phase -ceq 'InvokePester' -and $produced.Failures[0].File -ceq 'suite.ps1' -and $produced.Failures[0].Line -eq 1) '真正ErrorRecord只保留允許相對來源與固定階段'
Assert (-not([IO.File]::ReadAllText($file).Contains('PRIVATE-MESSAGE') -or [IO.File]::ReadAllText($file).Contains($temp))) '原生例外message與絕對路徑不進sidecar'
Write-PesterWorkerFailureRecord -Path $file -SourceRoot $temp -AllowedFiles @('other.ps1') -InvocationErrors @($original)
$produced=Get-Content -LiteralPath $file -Raw|ConvertFrom-Json
Assert ($produced.Failures[0].File -ceq '' -and $produced.Failures[0].Line -eq 0) '不允許來源保留未知位置，不宣稱私有路徑為公開'
Write-Host 'ALL PASS: bounded strict failure-sidecar validation.'
