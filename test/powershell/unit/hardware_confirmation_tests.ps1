#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '../../../core/hardware.ps1')
$count=0
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Message)};$script:count++}
function Refuse([scriptblock]$Action,[string]$Message){$rejected=$false;try{& $Action|Out-Null}catch{$rejected=$true};Assert $rejected $Message}
$unknown=Get-SetupHardwareProfile -BoardProduct '' -ConfirmedBoard 'NUC8i7HVB' -ConfirmationComputer $env:COMPUTERNAME
Assert ($unknown.IsNuc8 -and $unknown.BoardProduct -eq '' -and $unknown.DriverBoard -eq 'NUC8i7HVB' -and $unknown.DetectionStatus -eq 'Unknown') '未知主機允許明確確認，但保留原始空板號與 unknown 證據'
Assert (-not (Get-SetupModuleDecision 'apply_amd_privacy_settings.ps1' $unknown).Applicable) '手動驅動確認不擴大 AMD 偏好模組適用性'
Refuse {Get-SetupHardwareProfile -BoardProduct 'Other Board' -ConfirmedBoard NUC8i7HVB -ConfirmationComputer $env:COMPUTERNAME} '已知其他主機不可覆寫'
Refuse {Get-SetupHardwareProfile -BoardProduct NUC8i7HNB -ConfirmedBoard NUC8i7HVB -ConfirmationComputer $env:COMPUTERNAME} '已偵測支援型號也不可與確認型號衝突'
Refuse {Get-SetupHardwareProfile -BoardProduct '' -ConfirmedBoard NUC8i7HVB -ConfirmationComputer 'different_machine'} '其他電腦確認不可沿用'
Refuse {Get-SetupHardwareProfile -BoardProduct '' -ConfirmedBoard NUC8i7HVB} '確認必須附目前機器身分'
Refuse {Get-SetupHardwareProfile -BoardProduct '' -ConfirmedBoard 'Other Board' -ConfirmationComputer $env:COMPUTERNAME} '確認僅允許既有板號白名單'
function Get-CimInstance {throw 'fixture CIM unavailable'}
$failed=Get-SetupHardwareProfile
Assert ($failed.DetectionStatus -eq 'Unknown' -and -not $failed.IsNuc8 -and $failed.DetectionError -match 'CIM unavailable') 'CIM 失敗回報未知及錯誤，不中斷通用設定'
Remove-Item Function:Get-CimInstance
function Get-CimInstance { @([pscustomobject]@{Product='NUC8i7HVB'},[pscustomobject]@{Product='Other Board'}) }
Refuse {Get-SetupHardwareProfile -ConfirmedBoard NUC8i7HVB -ConfirmationComputer $env:COMPUTERNAME} '多塊板含已知不符不得手動覆寫'
Write-Host ('ALL PASS: '+$count+' hardware confirmation assertions; no host changes.')