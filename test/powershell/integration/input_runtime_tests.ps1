#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$library=Join-Path $root 'modules/input/input_method_library.ps1'
Assert (Test-Path -LiteralPath $library) '輸入法可由正式具名來源安全呼叫並保留完整coverage分母'
. $library
function Get-WinUserLanguageList {return ,@([pscustomobject]@{LanguageTag='en-US';InputMethodTips=@('0409:00000409')})}
function Get-WinDefaultInputMethodOverride {[pscustomobject]@{InputMethodTip='0409:00000409'}}
function Set-WinUserLanguageList {throw 'VerifyOnly attempted language mutation'}
function Set-WinDefaultInputMethodOverride {throw 'VerifyOnly attempted override mutation'}
function New-Item {throw 'VerifyOnly attempted disk write'}
function Set-Content {throw 'VerifyOnly attempted report write'}
$r=Invoke-SetupInputMethodSettings -VerifyOnly -ReportPath (Join-Path $env:TEMP 'must_not_write_input.json')
Assert ($r.Success -and $r.VerifyOnly) 'VerifyOnly成功讀回且完全不寫設定或報告'
Write-Host 'ALL PASS: original input source; no real settings or report writes.'