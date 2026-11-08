#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/test/powershell_worker_diagnostics.ps1')
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
Assert ((Get-Command Get-PowerShellWorkerFailureDiagnostic).Parameters.ContainsKey('FailureRecordPath')) 'parent診斷必須提供嚴格typed sidecar入口'
$temp=Join-Path $env:TEMP ('pester_schema_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
$file=Join-Path $temp 'failure.json'
function Read-Record([string]$Text){[IO.File]::WriteAllText($file,$Text,[Text.UTF8Encoding]::new($false));Get-PowerShellWorkerFailureDiagnostic -SourceRoot $temp -TestFile 'suite.ps1' -WorkerIndex 0 -Engine powershell -NativeExitCode 1 -FailureRecordPath $file -AllowedFiles @('suite.ps1')}
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
Write-Host 'ALL PASS: bounded strict failure-sidecar validation.'
