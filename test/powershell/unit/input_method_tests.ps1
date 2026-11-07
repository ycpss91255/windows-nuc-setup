#Requires -Version 5.1
# Isolated tests: all Windows language commands are mocked; only temporary report files are written.
$ErrorActionPreference='Stop'
$modulePath=Join-Path ([IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))) 'modules\input\apply_input_method_settings.ps1'
$body=[IO.File]::ReadAllText($modulePath) -replace '(?im)^#Requires -RunAsAdministrator\s*',''
$module=[scriptblock]::Create($body)
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('NUC-InputMethod-Test-'+[guid]::NewGuid().ToString('N'))
$originalProgramData=$env:ProgramData
$script:assertions=0
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Message)};$script:assertions++;Write-Host ('PASS: '+$Message)}
function Language([string]$Tag,[string[]]$Tips){
 $list=New-Object 'Collections.Generic.List[string]'
 foreach($tip in $Tips){$list.Add($tip)}
 [pscustomobject]@{LanguageTag=$Tag;InputMethodTips=$list}
}
function Reset-Case([object[]]$Languages,[string]$Default='0409:00000409'){
 $script:languages=New-Object 'Collections.Generic.List[object]'
 foreach($language in $Languages){$script:languages.Add($language)}
 $script:defaultTip=$Default;$script:setListCalls=0;$script:setDefaultCalls=0
 $script:ignoreListSet=$false
}
function Get-WinUserLanguageList {return ,$script:languages}
function New-WinUserLanguageList([string]$Language){
 # Intentionally return no keyboard so the missing-language branch must add it explicitly.
 return ,@(Language $Language @())
}
function Set-WinUserLanguageList($LanguageList,[switch]$Force){
 $script:setListCalls++
 if($script:ignoreListSet){$script:languages=New-Object 'Collections.Generic.List[object]';$script:languages.Add((Language 'zh-TW' @('zh-tip')))}
}
function Get-WinDefaultInputMethodOverride {[pscustomobject]@{InputMethodTip=$script:defaultTip}}
function Set-WinDefaultInputMethodOverride([string]$InputTip){$script:setDefaultCalls++;$script:defaultTip=$InputTip}
function Report {Get-Content -LiteralPath (Join-Path $env:ProgramData 'NUC8-Setup\InputMethod-Result.json') -Raw|ConvertFrom-Json}
function Run-FailingVerify {
 $caught=$false
 try{& $module -VerifyOnly}catch{$caught=$true}
 Assert $caught 'VerifyOnly rejects incomplete state'
 Assert ($script:setListCalls -eq 0 -and $script:setDefaultCalls -eq 0) 'VerifyOnly does not call either setter'
}
try{
 $env:ProgramData=$fixture
 Reset-Case @((Language 'zh-TW' @('zh-tip')),(Language 'ja-JP' @('ja-tip'))) 'zh-tip'
 & $module
 $r=Report
 Assert ($r.Success -and $r.EnglishLanguagePresent -and $r.USKeyboardPresent -and $r.DefaultInputMethodIsUS) 'missing en-US and missing default keyboard are added and verified'
 Assert (($script:languages.LanguageTag -join ',') -eq 'zh-TW,ja-JP,en-US') 'existing Chinese and Japanese language order preserved'
 Assert ($script:languages[0].InputMethodTips[0] -eq 'zh-tip') 'Chinese input method unchanged'
 Assert ($script:setListCalls -eq 1 -and $script:setDefaultCalls -eq 1) 'language update applied once'
 Reset-Case @((Language 'en-US' @('0409:00020409')),(Language 'zh-TW' @('zh-tip')))
 & $module
 Assert ((Report).Success) 'existing English missing US keyboard repaired'
 Assert (($script:languages[0].InputMethodTips -join ',') -eq '0409:00020409,0409:00000409') 'existing keyboard retained before added US keyboard'
 Assert (($script:languages.LanguageTag -join ',') -eq 'en-US,zh-TW') 'existing language order unchanged'
 Reset-Case @((Language 'zh-TW' @('zh-tip')),(Language 'en-US' @('0409:00000409')))
 & $module
 Assert ($script:setListCalls -eq 0 -and (Report).Success) 'already correct languages are not rewritten'
 $script:setDefaultCalls=0
 & $module -VerifyOnly
 Assert ($script:setListCalls -eq 0 -and $script:setDefaultCalls -eq 0 -and (Report).Success) 'valid VerifyOnly is read-only except report'
 Reset-Case @((Language 'zh-TW' @('zh-tip')))
 Run-FailingVerify
 Assert (-not (Report).EnglishLanguagePresent -and (Report).DefaultInputMethodIsUS) 'correct override alone cannot hide missing en-US'
 Reset-Case @((Language 'en-US' @('0409:00020409')),(Language 'zh-TW' @('zh-tip')))
 Run-FailingVerify
 Assert ((Report).EnglishLanguagePresent -and -not (Report).USKeyboardPresent) 'correct override alone cannot hide missing US keyboard'
 Reset-Case @((Language 'en-US' @('0409:00000409'))) 'zh-tip'
 Run-FailingVerify
 Assert (-not (Report).DefaultInputMethodIsUS -and (Report).USKeyboardPresent) 'wrong override rejected even with US keyboard present'
 Reset-Case @((Language 'zh-TW' @('zh-tip'))) 'zh-tip'
 $script:ignoreListSet=$true
 $caught=$false;try{& $module}catch{$caught=$true}
 Assert ($caught -and -not (Report).Success) 'apply re-reads system state and rejects unsuccessful language persistence'
 Write-Host ('ALL PASS: '+$script:assertions+' isolated assertions. No real user language settings changed.')
}finally{$env:ProgramData=$originalProgramData}
