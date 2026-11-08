#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'script/test/ci_tasks.ps1')
function Assert([bool]$Passed,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Passed}|ConvertTo-Json -Compress));if(-not $Passed){throw $Name}}
Assert ([bool](Get-Command Export-CIPowerShellRawEvidence -ErrorAction SilentlyContinue)) 'raw輸出判斷須位於可量測的正式具名controller'
$temp=Join-Path $env:TEMP ('ci_raw_controller_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
$script:calls=@();$script:fail=$false
function Invoke-CINative {param($File,$Arguments);$script:calls+=@([pscustomobject]@{File=$File;Arguments=@($Arguments)});if($script:fail){throw 'native fixture exit 7'}}
$text=@(Export-CIPowerShellRawEvidence -SourceRoot $root -RunnerTemp $temp 6>&1)|Out-String
Assert ($script:calls.Count -eq 0 -and $text.Contains('No completed PowerShell raw evidence') -and -not $text.Contains($temp)) '缺raw明確安全訊息且不呼叫native'
$input=Join-Path $temp 'repo-coverage/powershell';[void][IO.Directory]::CreateDirectory($input)
[IO.File]::WriteAllText((Join-Path $input 'evidence.json'),'synthetic fixture handled by native-boundary double')
$failed=$false;try{Export-CIPowerShellRawEvidence -SourceRoot $root -RunnerTemp $temp}catch{$failed=$true}
Assert ($failed -and $script:calls.Count -eq 0) '有raw缺驗證工具不得假裝已匯出'
$tool=Join-Path $temp 'repo-coverage/repo_coverage_tool.exe';[IO.File]::WriteAllText($tool,'never executed')
Export-CIPowerShellRawEvidence -SourceRoot $root -RunnerTemp $temp
Assert ($script:calls.Count -eq 1 -and $script:calls[0].File -eq $tool -and ($script:calls[0].Arguments -join '|') -ceq (@('export-powershell','--source-root',$root,'--evidence-dir',$input,'--output-dir',(Join-Path $temp 'powershell-raw-public')) -join '|')) '完整時只呼叫正式驗證exportCLI並保留所有來源參數'
$script:fail=$true;$failed=$false;try{Export-CIPowerShellRawEvidence -SourceRoot $root -RunnerTemp $temp}catch{$failed=$true}
Assert ($failed -and $script:calls.Count -eq 2) 'native驗證失敗必須往上失敗，不降級為缺raw'
Write-Host 'ALL PASS: measured raw controller; TEMP and native boundary doubles only'
