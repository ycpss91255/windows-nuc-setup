#Requires -Version 5.1
$ErrorActionPreference='Stop'
$packageRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
. (Join-Path $packageRoot 'core\Hardware.ps1')
$count=0
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw ('FAIL: '+$Message)};$script:count++;Write-Host ('PASS: '+$Message)}
$generic=Get-SetupHardwareProfile -BoardProduct 'Other Board' -UICulture 'en-US'
$hv=Get-SetupHardwareProfile -BoardProduct 'NUC8i7HVB' -UICulture 'zh-TW' -DriverPackagePath 'selected_package'
$hn=Get-SetupHardwareProfile -BoardProduct 'NUC8i7HNB' -UICulture 'zh-TW' -DriverPackagePath 'selected_package'
Assert (-not $generic.IsNuc8) '其他主機板使用通用設定檔'
Assert ($hv.IsNuc8 -and $hn.IsNuc8) '兩種 NUC 主機板皆匹配'
Assert (-not (Get-SetupHardwareProfile -BoardProduct 'NUC8i7HVB-extra').IsNuc8) '不以部分字串誤判 NUC'
foreach($module in @('Install-Drivers.ps1','Apply-AMDPrivacySettings.ps1')){
 Assert (-not (Get-SetupModuleDecision $module $generic).Applicable) ('通用主機略過 '+$module)
 Assert ((Get-SetupModuleDecision $module $hn).Applicable) ('匹配主機可執行 '+$module)
}
Assert ((Get-SetupModuleDecision 'Apply-InputMethodSettings.ps1' $generic).Applicable) '通用模組不受機型限制'
Assert (-not (Get-SetupModuleDecision 'Desktop-IconLayout.ps1' $generic).Applicable) '非繁體中文僅略過圖示座標'
Assert ((Get-SetupModuleDecision 'Desktop-IconLayout.ps1' $hv).Applicable) '繁體中文圖示座標可套用'
$skip=New-SetupSkippedCheck 'AMD' '不適用'
Assert ($skip.Status -eq 'Skipped' -and $null -eq $skip.Passed) '略過不偽裝為通過'
Assert (Test-SetupChecksPassed @($skip,[pscustomobject]@{Status='Passed';Passed=$true})) '驗收忽略不適用檢查'
Assert (-not (Test-SetupChecksPassed @($skip,[pscustomobject]@{Status='Failed';Passed=$false}))) '有真實失敗仍不通過'
$unselected=Get-SetupHardwareProfile -BoardProduct 'NUC8i7HVB' -UICulture 'zh-TW'
Assert (-not (Get-SetupModuleDecision 'Install-Drivers.ps1' $unselected).Applicable) 'NUC 未選擇驅動包也明確略過'
Assert ((Test-SetupDriverPayload $unselected '').Status -eq 'Skipped') '未選擇包不要求任何 payload'

Write-Host ('ALL PASS: '+$count+' hardware unit assertions; no host changes.')
