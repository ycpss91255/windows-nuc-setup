#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/test/run_repo_coverage.ps1')
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Action,[string]$Name){$caught=$false;try{& $Action|Out-Null}catch{$caught=$true};Assert $caught $Name}
$temp=Join-Path $env:TEMP ('repo_pipeline_'+[guid]::NewGuid().ToString('N'));$public=Join-Path $temp 'public';[void][IO.Directory]::CreateDirectory($public)
[IO.File]::WriteAllText((Join-Path $public 'summary.json'),('{"Commit":"'+('a'*40)+'","RunUrl":"https://github.com/example/repo/actions/runs/1"}'))
$script:calls=New-Object Collections.Generic.List[object]
function Invoke-CINative {param($File,$Arguments) $script:calls.Add(@{File=$File;Arguments=@($Arguments)});if($script:failAt -and @($Arguments) -contains $script:failAt){throw 'fixture failure'}}
try {
 $output=Join-Path $temp 'result'
 Invoke-RepoCoveragePipeline -SourceRoot $root -PublicDirectory $public -GoCoverageDirectory (Join-Path $temp 'go') -ManagedEvidencePath (Join-Path $temp 'managed/evidence.json') -OutputDirectory $output
 $collect=@($script:calls|Where-Object {$_.Arguments -contains 'collect'})
 Assert ($collect.Count -eq 1 -and ($collect[0].Arguments -contains '--go-evidence') -and ($collect[0].Arguments -contains '--powershell-evidence') -and ($collect[0].Arguments -contains '--cmd-evidence') -and ($collect[0].Arguments -contains '--managed-evidence')) '四種語言原始證據一起收集'
 $verify=@($script:calls|Where-Object {$_.Arguments -contains 'verify'})
 Assert ($verify.Count -eq 1 -and ($verify[0].Arguments -contains '--require-complete') -and ($verify[0].Arguments -contains '--minimum-percent') -and ($verify[0].Arguments -contains '80')) '正式門檻要求完整與八成'
 Assert ($script:calls[-1].Arguments -contains (Join-Path $root 'script/test/attach_repo_coverage.ps1')) '通過門檻才附加正式報告'
 Reject {Invoke-RepoCoveragePipeline -SourceRoot $root -PublicDirectory $public -GoCoverageDirectory 'go' -ManagedEvidencePath 'managed' -OutputDirectory $output} '不得混入已有量測目錄'
 $script:calls.Clear();$script:failAt='verify'
 Reject {Invoke-RepoCoveragePipeline -SourceRoot $root -PublicDirectory $public -GoCoverageDirectory 'go' -ManagedEvidencePath 'managed' -OutputDirectory (Join-Path $temp 'failed')} 'strict失敗必須停止'
 Assert (@($script:calls|Where-Object {$_.Arguments -contains (Join-Path $root 'script/test/attach_repo_coverage.ps1')}).Count -eq 0) '缺量測或低覆蓋率不附加發布報告'
 Reject {Invoke-RepoCoveragePipeline -SourceRoot $root -PublicDirectory $public -GoCoverageDirectory 'go' -ManagedEvidencePath 'managed' -OutputDirectory (Join-Path $root 'coverage_invalid')} '產物不得寫入版本來源'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force}
