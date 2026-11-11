#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
function Reject([scriptblock]$Action,[string]$Name){$caught=$false;try{& $Action|Out-Null}catch{$caught=$true};Assert $caught $Name}
$lib=Join-Path $root 'modules/updates/update_progress_library.ps1'
Assert (Test-Path $lib) '更新進度有可安全載入的具名來源'
. $lib
function Start-Sleep {param($Seconds)}
$script:events=@();$script:seen=@();$script:failEnd=$false;$script:failProgress=$false
function Write-SetupUpdateProgress {param($Path,$Stage,$Detail,$PercentComplete,$CurrentUpdate,$TotalUpdates,$CurrentTitle,$CurrentPercent) $script:seen+=@{Stage=$Stage;Percent=$PercentComplete;Current=$CurrentUpdate;Total=$TotalUpdates;Title=$CurrentTitle;ItemPercent=$CurrentPercent}}
function New-SetupUpdateCallback {return New-Object PSObject}
function New-FakeJob {
 $j=[pscustomobject]@{IsCompleted=$false;Index=0;Never=$false}
 $j|Add-Member ScriptMethod GetProgress {$script:events+='Progress';if($script:failProgress){throw 'fixture progress fail'};$p=@(25,70,100)[$this.Index];$i=[math]::Min(1,$this.Index);if(-not $this.Never){$this.Index++;if($this.Index -eq 3){$this.IsCompleted=$true}};[pscustomobject]@{PercentComplete=$p;CurrentUpdateIndex=$i;CurrentUpdatePercentComplete=50}}
 $j|Add-Member ScriptMethod RequestAbort {$script:events+='Abort';$this.IsCompleted=$true}
 $j|Add-Member ScriptMethod CleanUp {$script:events+='CleanUp';$script:cleanupSawFailure=($script:seen[-1].Stage -eq '更新未完成')}
 return $j
}
function New-FakeClient {
 $c=[pscustomobject]@{Job=(New-FakeJob);IsBusy=$false}
 foreach($op in @('Download','Install')){
  $c|Add-Member ScriptMethod ('Begin'+$op) {param($progress,$completed,$state) if($null -eq $progress -or $null -eq $completed){throw 'null callbacks forbidden'};$script:events+='Begin';return $this.Job}
  $c|Add-Member ScriptMethod ('End'+$op) {param($job) $script:events+='End';if(-not $job.IsCompleted){throw 'end before complete'};if($script:failEnd){throw 'fixture end fail'};[pscustomobject]@{ResultCode=2;RebootRequired=$true}}
 }
 return $c
}
foreach($op in @('Download','Install')){
 $script:events=@();$script:seen=@();$client=New-FakeClient
 $r=Invoke-SetupUpdateOperation -Operation $op -Client $client -Titles @('first','second') -ProgressPath 'unused.json' -PollSeconds 0
 Assert ($r.ResultCode -eq 2 -and $r.RebootRequired) ($op+'保留真End結果')
 Assert (($script:seen.Percent -join ',') -eq '25,70,100') ($op+'顯示API真百分比而非時間估計')
 Assert ($script:seen[1].Current -eq 2 -and $script:seen[1].Total -eq 2 -and $script:seen[1].Title -eq 'second' -and $script:seen[1].ItemPercent -eq 50) ($op+'記錄當前項目總數標題單項進度')
 Assert (($script:events -join ',') -eq 'Begin,Progress,Progress,Progress,End,CleanUp') ($op+'只啟動一次完成後End並Cleanup')
}
$client=New-FakeClient;$client.IsBusy=$true;$script:events=@();Reject {Invoke-SetupUpdateOperation -Operation Install -Client $client -Titles a -ProgressPath x} 'installer busy不雙重啟動';Assert ($script:events.Count -eq 0) 'busy完全不呼叫Begin'
$client=New-FakeClient;$client.Job.Never=$true;$script:events=@();Reject {Invoke-SetupUpdateOperation -Operation Download -Client $client -Titles a -ProgressPath x -TimeoutSeconds 0 -PollSeconds 0} '下載超時明確失敗';Assert ($script:events -contains 'Abort' -and $script:events -contains 'CleanUp' -and @($script:events|Where-Object {$_ -eq 'Begin'}).Count -eq 1) '超時只中止自己工作並清理不重啟';Assert $script:cleanupSawFailure '進入可能阻塞的COM清理前已保存失敗進度'
$client=New-FakeClient;$script:failEnd=$true;$script:events=@();Reject {Invoke-SetupUpdateOperation -Operation Install -Client $client -Titles a -ProgressPath x -PollSeconds 0} 'End錯誤如實失敗';Assert ($script:events[-1] -eq 'CleanUp') 'End失敗仍Cleanup';$script:failEnd=$false
$client=New-FakeClient;$script:failProgress=$true;$script:events=@();Reject {Invoke-SetupUpdateOperation -Operation Download -Client $client -Titles a -ProgressPath x -PollSeconds 0} '進度API錯誤不假成功';Assert ($script:events -contains 'Abort' -and $script:events[-1] -eq 'CleanUp') '進度失敗清理自己job';$script:failProgress=$false
# Reload the named library to test the real constructor, not the fake WUA operation boundary.
. $lib
$a=New-SetupUpdateCallback;$b=New-SetupUpdateCallback
Assert ($a.GetType().FullName -eq 'WindowsSetup.UpdateCallback' -and $b.GetType().FullName -eq 'WindowsSetup.UpdateCallback') '真原檔callback建構首次編譯與重用類型均成功'
$a.Invoke($null,$null);$b.Invoke($null,$null)
Write-Host 'ALL PASS: fake WUA boundaries, original orchestration only'