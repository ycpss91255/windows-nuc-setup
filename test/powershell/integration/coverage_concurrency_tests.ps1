#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$collector=Join-Path $root 'script/test/powershell_coverage.ps1'
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
Assert ((Get-Command $collector).Parameters.ContainsKey('ThrottleLimit')) '收集器必須提供上限兩個 worker 的可選並行'
$temp=Join-Path $env:TEMP ("coverage 中文 ' quote "+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
function Write-Fixture([string]$Name,[string]$Text){[IO.File]::WriteAllText((Join-Path $temp $Name),$Text,[Text.UTF8Encoding]::new($true))}
Write-Fixture 'source.ps1' @'
function Choose([bool]$Positive){if($Positive){return 1}else{return 2}}
function NeverCalled {return 99}
'@
foreach($index in @(0,1)){
 $positive=if($index -eq 0){'$true'}else{'$false'}
 Write-Fixture ('side_'+$index+'.Tests.ps1') @"
BeforeAll { . (Join-Path `$PSScriptRoot 'source.ps1') }
Describe 'real complementary source' {
 It 'uses one branch' {
  [IO.File]::WriteAllText((Join-Path `$PSScriptRoot ('start_'+$index+'.json')),(@{PID=`$PID;Ticks=[DateTime]::UtcNow.Ticks}|ConvertTo-Json))
  if(`$env:WINDOWS_SETUP_SYNTHETIC_OVERLAP -eq '1'){
   `$watch=[Diagnostics.Stopwatch]::StartNew()
   while(-not(Test-Path (Join-Path `$PSScriptRoot ('start_'+(1-$index)+'.json')))){if(`$watch.Elapsed.TotalSeconds -gt 15){throw 'second native worker never overlapped'};Start-Sleep -Milliseconds 50}
  }
  Write-Host 'PRIVATE-STDOUT-SENTINEL'
  Choose $positive | Should-Be $(1+$index)
  [IO.File]::WriteAllText((Join-Path `$PSScriptRoot ('end_'+$index+'.json')),(@{Ticks=[DateTime]::UtcNow.Ticks}|ConvertTo-Json))
 }
}
"@
}
$manifest=Join-Path $temp 'manifest.json'
@{SourceRoot=$temp;Sources=@('source.ps1');Tests=@('side_0.Tests.ps1','side_1.Tests.ps1')}|ConvertTo-Json -Depth 5|Set-Content $manifest -Encoding UTF8
function Collect([int]$Limit,[string]$Name){
 $output=Join-Path $temp $Name;$log=Join-Path $temp ($Name+'.private.log')
 $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$collector,'-ManifestPath',$manifest,'-OutputDirectory',$output);if($Limit -ne 1){$arguments+=@('-ThrottleLimit',$Limit)}
 & powershell.exe @arguments *> $log
 Assert ($LASTEXITCODE -eq 0) ('真 native worker 收集成功 '+$Name)
 Assert (-not([IO.File]::ReadAllText($log).Contains('PRIVATE-STDOUT-SENTINEL'))) ('stdout 只留在私有 worker 檔 '+$Name)
 foreach($index in @(0,1)){Assert ([IO.File]::ReadAllText((Join-Path $output ('worker_'+$index+'.private.stdout.log'))).Contains('PRIVATE-STDOUT-SENTINEL')) ('worker stdout確實保留於私有檔 '+$index)}
 return $output
}
$prior=$env:WINDOWS_SETUP_SYNTHETIC_OVERLAP
try{
 $env:WINDOWS_SETUP_SYNTHETIC_OVERLAP='0';$sequential=Collect 1 'sequential'
 foreach($name in @('start_0.json','start_1.json','end_0.json','end_1.json')){Remove-Item -LiteralPath (Join-Path $temp $name)}
 $env:WINDOWS_SETUP_SYNTHETIC_OVERLAP='1';$parallel=Collect 2 'parallel'
 Assert ((Get-FileHash (Join-Path $sequential 'coverage.xml')).Hash -ceq (Get-FileHash (Join-Path $parallel 'coverage.xml')).Hash) '序列與並行完整行計數逐位元一致'
 $a=Get-Content (Join-Path $sequential 'evidence.json') -Raw|ConvertFrom-Json;$b=Get-Content (Join-Path $parallel 'evidence.json') -Raw|ConvertFrom-Json
 Assert ($a.Covered -eq $b.Covered -and $a.Total -eq $b.Total -and ($a.Sources|ConvertTo-Json -Depth 8 -Compress) -ceq ($b.Sources|ConvertTo-Json -Depth 8 -Compress)) '來源 hash 與完整分母一致'
 foreach($index in @(0,1)){
  $first=Get-Content (Join-Path $sequential ('worker_'+$index+'.json')) -Raw|ConvertFrom-Json;$second=Get-Content (Join-Path $parallel ('worker_'+$index+'.json')) -Raw|ConvertFrom-Json
  Assert (($first.Commands|ConvertTo-Json -Depth 8 -Compress) -ceq ($second.Commands|ConvertTo-Json -Depth 8 -Compress)) ('各 index 完整 raw Commands 一致 '+$index)
  $start=Get-Content (Join-Path $temp ('start_'+$index+'.json')) -Raw|ConvertFrom-Json
  Assert ($second.ProcessId -eq $start.PID -and $b.Workers[$index].Index -eq $index) ('記錄實際 native PID 與排序 '+$index)
 }
 $start0=(Get-Content (Join-Path $temp 'start_0.json') -Raw|ConvertFrom-Json).Ticks;$start1=(Get-Content (Join-Path $temp 'start_1.json') -Raw|ConvertFrom-Json).Ticks
 $end0=(Get-Content (Join-Path $temp 'end_0.json') -Raw|ConvertFrom-Json).Ticks;$end1=(Get-Content (Join-Path $temp 'end_1.json') -Raw|ConvertFrom-Json).Ticks
 Assert ($start0 -lt $end1 -and $start1 -lt $end0) '兩個 native worker 真正重疊執行'
 Assert ($b.Covered -eq 1 -and $b.Total -eq 2) '互補同一行完整命中且nevercalled仍零命中'
 foreach($invalid in @(0,3)){$ErrorActionPreference='Continue';& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $collector -ManifestPath $manifest -OutputDirectory (Join-Path $temp ('invalid_'+$invalid)) -ThrottleLimit $invalid *> (Join-Path $temp ('invalid_'+$invalid+'.private.log'));$code=$LASTEXITCODE;$ErrorActionPreference='Stop';Assert ($code -ne 0) ('拒絕超出1到2範圍 '+$invalid)}
 Write-Fixture 'failed.Tests.ps1' @'
Describe 'failure' {It 'fails after peer starts' {$watch=[Diagnostics.Stopwatch]::StartNew();while(-not(Test-Path (Join-Path $PSScriptRoot 'pending_pid.json'))){if($watch.Elapsed.TotalSeconds -gt 15){throw 'pending peer never started'};Start-Sleep -Milliseconds 50};1|Should-Be 2}}
'@
 Write-Fixture 'pending.Tests.ps1' @'
Describe 'pending' {It 'waits until coordinator terminates it' {[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'pending_pid.json'),$PID.ToString());Start-Sleep -Seconds 30}}
'@
 @{SourceRoot=$temp;Sources=@('source.ps1');Tests=@('failed.Tests.ps1','pending.Tests.ps1')}|ConvertTo-Json -Depth 5|Set-Content $manifest -Encoding UTF8
 $failed=Join-Path $temp 'failed'
 $ErrorActionPreference='Continue'
 & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $collector -ManifestPath $manifest -OutputDirectory $failed -ThrottleLimit 2 *> (Join-Path $temp 'failure.private.log')
 $code=$LASTEXITCODE;$ErrorActionPreference='Stop'
 Assert ($code -ne 0 -and -not(Test-Path (Join-Path $failed 'evidence.json'))) '失敗 worker 保留非零且不發布彙總'
 $pendingId=[int]([IO.File]::ReadAllText((Join-Path $temp 'pending_pid.json')))
 Assert ($null -eq (Get-Process -Id $pendingId -ErrorAction SilentlyContinue)) '失敗後其他自建 native worker 已終止不殘留'
}finally{$env:WINDOWS_SETUP_SYNTHETIC_OVERLAP=$prior}
Write-Host 'ALL PASS: bounded native concurrency; TEMP synthetic fixtures only'
