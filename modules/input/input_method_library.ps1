#Requires -Version 5.1
function Get-SetupInputMethodState {
 param([switch]$VerifyOnly)
 $englishTag='en-US';$usInputTip='0409:00000409'
$actualLanguages=Get-WinUserLanguageList
$actualEnglish=@($actualLanguages|Where-Object LanguageTag -eq $englishTag)
$hasEnglish=$actualEnglish.Count -gt 0
$hasUSKeyboard=$hasEnglish -and ($usInputTip -in $actualEnglish[0].InputMethodTips)
$actual=Get-WinDefaultInputMethodOverride
$defaultIsUS=$actual.InputMethodTip -eq $usInputTip
$errors=@()
if(-not $hasEnglish){$errors+='使用者語言清單缺少英文（美國）en-US。'}
elseif(-not $hasUSKeyboard){$errors+='英文（美國）缺少美式鍵盤 0409:00000409。'}
if(-not $defaultIsUS){$errors+='預設輸入法不是英文美式鍵盤 0409:00000409。'}
$success=$hasEnglish -and $hasUSKeyboard -and $defaultIsUS
[ordered]@{
 Success=$success
 EnglishLanguagePresent=$hasEnglish
 USKeyboardPresent=$hasUSKeyboard
 DefaultInputMethodIsUS=$defaultIsUS
 DefaultInputMethod=$actual.InputMethodTip
 LanguageTags=@($actualLanguages.LanguageTag)
 EnglishInputMethodTips=@($actualEnglish|ForEach-Object {$_.InputMethodTips})
 Errors=$errors
 VerifyOnly=[bool]$VerifyOnly
 CheckedAt=(Get-Date).ToString('o')
}
}
function Invoke-SetupInputMethodSettings {
 param([switch]$VerifyOnly,[string]$ReportPath=(Join-Path $env:ProgramData 'NUC8-Setup/InputMethod-Result.json'))
$englishTag='en-US'
$usInputTip='0409:00000409'
if(-not $VerifyOnly){
 $languages=Get-WinUserLanguageList
 $english=@($languages|Where-Object LanguageTag -eq $englishTag)
 $changed=$false
 if(-not $english.Count){
  $newEnglish=(New-WinUserLanguageList $englishTag)[0]
  $languages.Add($newEnglish)
  $english=@($newEnglish)
  $changed=$true
 }
 # Keep all existing languages, keyboard layouts and their order.
 if($usInputTip -notin $english[0].InputMethodTips){
  $english[0].InputMethodTips.Add($usInputTip)
  $changed=$true
 }
 if($changed){Set-WinUserLanguageList $languages -Force}
 Set-WinDefaultInputMethodOverride -InputTip $usInputTip
}
$result=Get-SetupInputMethodState -VerifyOnly:$VerifyOnly
if(-not $VerifyOnly){
 New-Item -ItemType Directory -Path (Split-Path $ReportPath -Parent) -Force|Out-Null
 $result|ConvertTo-Json -Depth 4|Set-Content -LiteralPath $ReportPath -Encoding UTF8
}
if(-not $result.Success){throw ('英文美式鍵盤驗證失敗：'+($result.Errors -join ' '))}
Write-Host '已確認英文（美國）與美式鍵盤存在，且為預設輸入法；保留中文及其他語言，可用 Win + Space 切換。已開啟的視窗可能仍保留原輸入法。' -ForegroundColor Green
return $result
}
