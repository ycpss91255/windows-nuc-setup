#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/test/ci_tasks.ps1')
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
function Reject([scriptblock]$Action,[string]$Name){$caught=$false;try{& $Action|Out-Null}catch{$caught=$true};Assert $caught $Name}
Invoke-CINative -File cmd.exe -Arguments @('/d','/c','exit 0')
Assert $true '原生成功返回保留'
Reject {Invoke-CINative -File cmd.exe -Arguments @('/d','/c','exit 7')} '原生非零返回拒絕'
Reject {Invoke-CINative -File '__missing_ci_executable__.exe'} '不存在的工具不能冒稱成功'
$passing=@{Tests='success';Requirements='success';Docker='success';Payload='success'}
Assert-CIResults $passing
Assert $true '四個必要工作成功才通過'
foreach($name in @('Tests','Requirements','Docker','Payload')){foreach($state in @('failure','cancelled','skipped','')){$copy=$passing.Clone();$copy[$name]=$state;Reject {Assert-CIResults $copy} ('必要工作拒絕 '+$name+' '+$state)}}
$copy=$passing.Clone();$copy.Remove('Payload');Reject {Assert-CIResults $copy} '設定包工作不可遺漏'
$main=Get-CIPortalParameters -Repository 'example/repo' -OutputDirectory 'out' -EventRef 'refs/heads/main' -RunId '42'
Assert ($main.MainRunId -eq '42' -and $main.Repository -eq 'example/repo') 'main明確指定同次執行'
$tag=Get-CIPortalParameters -Repository 'example/repo' -OutputDirectory 'out' -EventRef 'refs/tags/v1.0.0' -RunId '42'
Assert (-not $tag.ContainsKey('MainRunId')) 'tag不得冒用main執行'
function Invoke-CINative {param($File,$Arguments) $script:lastCommand=@($File)+$Arguments;if($script:probeCode -ne 0){$e=[Exception]::new('fixture');$e.Data['ExitCode']=$script:probeCode;throw $e}}
$script:probeCode=23
Assert-CIDockerFailure -Image 'example:test'
Assert ($script:lastCommand[0] -eq 'docker.exe' -and ($script:lastCommand -contains '--network') -and $script:lastCommand[-1] -eq 'exit 23') '容器退出probe不開啟網路'
foreach($code in @(0,1,24)){$script:probeCode=$code;Reject {Assert-CIDockerFailure -Image 'example:test'} ('真實返回碼必須23 '+$code)}
function Invoke-CINative {throw 'missing executable'}
Reject {Assert-CIDockerFailure -Image 'example:test'} '未啟動Docker不得當成正確失敗'
$temp=Join-Path $env:TEMP ('ci_tasks_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
try{
 [IO.File]::WriteAllText((Join-Path $temp 'summary.json'),'{"Environment":"Windows container / fixture"}')
 Assert-CIContainerReport $temp
 Assert $true '真container標示可接受'
 [IO.File]::WriteAllText((Join-Path $temp 'summary.json'),'{"Environment":"Windows host"}')
 Reject {Assert-CIContainerReport $temp} 'host報表不可充當container'
}finally{Remove-Item -LiteralPath $temp -Recurse -Force}
