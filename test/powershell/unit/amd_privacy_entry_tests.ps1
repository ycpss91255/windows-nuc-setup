#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$library=Join-Path $root 'modules/amd/amd_privacy_library.ps1'
Assert (Test-Path -LiteralPath $library) 'AMD既有演算法提供可直接隔離執行的正式具名函式'
. $library
$fixture=Join-Path $env:TEMP ('amd_privacy_'+[guid]::NewGuid().ToString('N'));$moduleRoot=Join-Path $fixture 'modules/amd';[void][IO.Directory]::CreateDirectory($moduleRoot);[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'core'))
[IO.File]::WriteAllText((Join-Path $fixture 'core/hardware.ps1'),'function Get-SetupHardwareProfile {[pscustomobject]@{IsNuc8=$global:AmdFixture.Applicable}};function Get-SetupModuleDecision {param($Module,$Hardware) [pscustomobject]@{Applicable=$Hardware.IsNuc8;Reason=''fixture generic''}}',[Text.UTF8Encoding]::new($true))
$family='AdvancedMicroDevicesInc-2.AMDRadeonSoftware_0a9344xs7nr4m'
function Test-Path {param($Path,$LiteralPath) $p=if($LiteralPath){$LiteralPath}else{$Path};if($p -like 'HK*:*'){return $global:AmdFixture.Registry.ContainsKey($p)};Microsoft.PowerShell.Management\Test-Path -LiteralPath $p}
function New-Item {param($Path,$ItemType,[switch]$Force) if($Path -like 'HK*:*'){$global:AmdFixture.Registry[$Path]=@{}}else{Microsoft.PowerShell.Management\New-Item -Path $Path -ItemType $ItemType -Force:$Force}}
function Get-ItemProperty {param($Path,$ErrorAction) $global:AmdFixture.Reads++;if($global:AmdFixture.Registry.ContainsKey($Path)){[pscustomobject]$global:AmdFixture.Registry[$Path]}else{[pscustomobject]@{}}}
function New-ItemProperty {param($Path,$Name,$PropertyType,$Value,[switch]$Force) $global:AmdFixture.Writes++;$global:AmdFixture.Registry[$Path][$Name]=$Value}
$oldProgramData=$env:ProgramData
try{
 foreach($mode in @('apply','existing_policy','verify','verify_failure','generic')){
  $env:ProgramData=Join-Path $fixture $mode
  $global:AmdFixture=@{Applicable=($mode -ne 'generic');Registry=@{};Writes=0;Reads=0}
  $policy='HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy';$consent='HKCU:\Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location\'+$family
  if($mode -in @('apply','existing_policy')){$global:AmdFixture.Registry[$policy]=@{LetAppsAccessLocation_ForceDenyTheseApps=@('other.deny');LetAppsAccessLocation_ForceAllowTheseApps=@('other.allow',$family);LetAppsAccessLocation_UserInControlOfTheseApps=@($family,'other.user')};if($mode -eq 'existing_policy'){$global:AmdFixture.Registry[$policy].LetAppsAccessLocation=1}}
  if($mode -eq 'verify'){$global:AmdFixture.Registry[$policy]=@{LetAppsAccessLocation_ForceDenyTheseApps=@($family)};$global:AmdFixture.Registry[$consent]=@{Value='Deny'}}
  $caught='';try{$result=@(Invoke-SetupAmdPrivacy -ModuleRoot $moduleRoot -EntryPath (Join-Path $moduleRoot 'apply_amd_privacy_settings.ps1') -VerifyOnly:($mode -in @('verify','verify_failure')))}catch{$caught=$_.Exception.Message}
  if($mode -eq 'generic'){Assert ($result[0].Applicable -eq $false -and $global:AmdFixture.Reads -eq 0 -and $global:AmdFixture.Writes -eq 0) 'Generic從正式硬體決策略過且不讀寫AMD政策';continue}
  $report=Get-Content -LiteralPath (Join-Path $env:ProgramData 'NUC8-Setup/AMDPrivacy-Result.json') -Raw|ConvertFrom-Json
  Assert ($report.Success -eq ($mode -ne 'verify_failure') -and ($caught -ne '') -eq ($mode -eq 'verify_failure')) ('真AMD讀回結果與例外一致 '+$mode)
  if($mode -in @('verify','verify_failure')){Assert ($global:AmdFixture.Writes -eq 0) ('VerifyOnly只讀設定，不重新apply '+$mode)}
  else{Assert ($global:AmdFixture.Registry[$policy].LetAppsAccessLocation_ForceDenyTheseApps -contains 'other.deny' -and $global:AmdFixture.Registry[$policy].LetAppsAccessLocation_ForceDenyTheseApps -contains $family -and $global:AmdFixture.Registry[$policy].LetAppsAccessLocation_ForceAllowTheseApps -notcontains $family -and $global:AmdFixture.Registry[$policy].LetAppsAccessLocation_ForceAllowTheseApps -contains 'other.allow' -and $global:AmdFixture.Registry[$policy].LetAppsAccessLocation_UserInControlOfTheseApps -contains 'other.user') '拒絕AMD同時保留其他App政策';Assert ($global:AmdFixture.Registry[$policy].LetAppsAccessLocation -eq $(if($mode -eq 'existing_policy'){1}else{0})) '保留既有全域政策，缺少才新增使用者控制'}
 }
}finally{$env:ProgramData=$oldProgramData;Remove-Variable AmdFixture -Scope Global -ErrorAction SilentlyContinue}
