#Requires -RunAsAdministrator
param([switch]$VerifyOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\..\core\Hardware.ps1')
$decision=Get-SetupModuleDecision -Module 'Apply-AMDPrivacySettings.ps1' -Hardware (Get-SetupHardwareProfile)
if(-not $decision.Applicable){Write-Host ('[略過] '+$decision.Reason);$decision;return}
$family='AdvancedMicroDevicesInc-2.AMDRadeonSoftware_0a9344xs7nr4m'
$policy='HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy'
$name='LetAppsAccessLocation_ForceDenyTheseApps'
$consent='HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location\'+$family
if(-not $VerifyOnly){
 if(-not(Test-Path $policy)){New-Item $policy -Force|Out-Null}
 $old=Get-ItemProperty $policy
 if($null -eq $old.LetAppsAccessLocation){New-ItemProperty $policy -Name LetAppsAccessLocation -PropertyType DWord -Value 0 -Force|Out-Null}
 $deny=@(@($old.$name)+$family|Where-Object {$_}|Select-Object -Unique)
 New-ItemProperty $policy -Name $name -PropertyType MultiString -Value $deny -Force|Out-Null
 foreach($other in @('LetAppsAccessLocation_ForceAllowTheseApps','LetAppsAccessLocation_UserInControlOfTheseApps')){
  if($family -in @($old.$other)){$keep=@($old.$other|Where-Object {$_ -and $_ -ne $family});New-ItemProperty $policy -Name $other -PropertyType MultiString -Value $keep -Force|Out-Null}
 }
 if(-not(Test-Path $consent)){New-Item $consent -Force|Out-Null}
 New-ItemProperty $consent -Name Value -PropertyType String -Value Deny -Force|Out-Null
}
$actual=Get-ItemProperty $policy -ErrorAction SilentlyContinue
$value=(Get-ItemProperty $consent -ErrorAction SilentlyContinue).Value
$success=($family -in @($actual.$name) -and $value -eq 'Deny')
$root=Join-Path $env:ProgramData 'NUC8-Setup'
New-Item -ItemType Directory $root -Force|Out-Null
[ordered]@{Success=$success;PackageFamilyName=$family;LocationConsent=$value;ForceDenyPolicy=($family -in @($actual.$name));VerifiedAt=(Get-Date).ToString('o')}|ConvertTo-Json|Set-Content (Join-Path $root 'AMDPrivacy-Result.json') -Encoding UTF8
if(-not $success){throw 'AMD Software 位置權限設定驗證失敗。'}
Write-Host '已確認 AMD Software 位置權限為拒絕；若程式已開啟，請關閉後重新開啟。' -ForegroundColor Green

