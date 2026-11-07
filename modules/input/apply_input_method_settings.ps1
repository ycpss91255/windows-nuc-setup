#Requires -Version 5.1
#Requires -RunAsAdministrator
param([switch]$VerifyOnly)
$ErrorActionPreference='Stop'
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
$root=Join-Path $env:ProgramData 'NUC8-Setup'
New-Item -ItemType Directory $root -Force|Out-Null
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
}|ConvertTo-Json -Depth 4|Set-Content (Join-Path $root 'InputMethod-Result.json') -Encoding UTF8
if(-not $success){throw ('英文美式鍵盤驗證失敗：'+($errors -join ' '))}
Write-Host '已確認英文（美國）與美式鍵盤存在，且為預設輸入法；保留中文及其他語言，可用 Win + Space 切換。已開啟的視窗可能仍保留原輸入法。' -ForegroundColor Green
