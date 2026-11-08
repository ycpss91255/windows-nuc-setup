#Requires -Version 5.1
. (Join-Path $PSScriptRoot 'start_pins_policy_library.ps1')
function Invoke-SetupStartMenuSettings {
 param([Parameter(Mandatory=$true)][string]$ModuleRoot,[Parameter(Mandatory=$true)][string]$OutputRoot,[switch]$VerifyOnly,[switch]$ApplyPolicy,[switch]$NonInteractive)
 $key='HKCU:\Software\Policies\Microsoft\Windows\Explorer'
 if(-not $VerifyOnly){
  if(-not(Test-Path $key)){New-Item $key -Force|Out-Null}
  New-ItemProperty $key -Name HideRecommendedSection -PropertyType DWord -Value 1 -Force|Out-Null
  $advanced='HKCU:\Software\Microsoft\Windows\CurrentVersion\explorer\Advanced'
  foreach($name in @('Start_TrackDocs','Start_TrackProgs','Start_IrisRecommendations')){New-ItemProperty $advanced -Name $name -PropertyType DWord -Value 0 -Force|Out-Null}
  $listKey='HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'
  if(-not(Test-Path $listKey)){New-Item $listKey -Force|Out-Null}
  New-ItemProperty $listKey -Name NoStartMenuMorePrograms -PropertyType DWord -Value 1 -Force|Out-Null
 }
 $result=Invoke-StartPinsConfiguration -AssetRoot (Join-Path $ModuleRoot 'assets') -OutputRoot $OutputRoot -VerifyOnly:$VerifyOnly -ApplyPolicy:$ApplyPolicy -NonInteractive:$NonInteractive
 if($result.Success -and (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer').NoStartMenuMorePrograms -ne 1){$result.Success=$false;$result.Status='Failed';$result.Error='開始選單應用程式清單設定未生效。'}
 return [pscustomobject]$result
}
