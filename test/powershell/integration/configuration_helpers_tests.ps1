#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$library=Join-Path $root 'core/configuration_library.ps1'
Assert (Test-Path -LiteralPath $library) '主流程提供可直接安全執行的具名來源'
. $library
$fixture=Join-Path $env:TEMP ('configuration_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
$source=[IO.File]::ReadAllText($library)
$names=@([regex]::Matches($source,"File='([^']+\.ps1)'" )|ForEach-Object {$_.Groups[1].Value})+@('apply_uac_settings.ps1','apply_autologon_settings.ps1','audit_nuc.ps1')
foreach($name in $names){[IO.File]::WriteAllText((Join-Path $fixture $name),@'
param($UserName,$AutoLogonPassword,$DriverPackagePath,$ConfirmedBoard,$ConfirmationComputer,[switch]$NonInteractive,[switch]$ApplyPolicy)
$name=[IO.Path]::GetFileName($PSCommandPath);$global:configurationFixture.Calls.Add($name)
if($name -eq 'install_drivers.ps1'){$global:configurationFixture.Driver=@{Path=$DriverPackagePath;Board=$ConfirmedBoard;Computer=$ConfirmationComputer;NonInteractive=[bool]$NonInteractive}}
if($name -eq 'apply_autologon_settings.ps1'){$global:configurationFixture.PasswordReceived=($AutoLogonPassword -ceq 'fixture-secret')}
if($name -eq $global:configurationFixture.Fail){throw 'fixture failure'}
if($name -eq 'apply_start_menu_settings.ps1'){[pscustomobject]@{Success=$true;Status='Confirmed';PinCount=0}}
'@,[Text.UTF8Encoding]::new($true))}
Copy-Item -LiteralPath (Join-Path $root 'modules/start_menu/start_pins_policy_library.ps1') -Destination $fixture
Copy-Item -LiteralPath (Join-Path $root 'modules/start_menu/start_pins_asset_library.ps1') -Destination $fixture
function Resolve-NucPath {param($Name) Join-Path $fixture $Name}
function Get-SetupModuleDecision {param($Module,$Hardware) [pscustomobject]@{Applicable=($Module -ne $global:configurationFixture.Skip);Reason='fixture skipped'}}
function Get-ItemProperty {param($Path) [pscustomobject]@{DefaultUserName='fixture';AutoAdminLogon='1'}}
function Get-PnpDevice {param([switch]$PresentOnly) if($global:configurationFixture.Problem){[pscustomobject]@{Status='Error'}}}
function Start-Transcript {param($Path) $global:configurationFixture.Transcript=$Path}
function Stop-Transcript {$global:configurationFixture.Stopped=$true;$global:configurationFixture.PasswordCleared=([string]::IsNullOrEmpty($AutoLogonPassword))}
function Test-Path {param($LiteralPath,$Path,$PathType) $p=if($LiteralPath){$LiteralPath}else{$Path};if($p -like 'HKLM:*'){return $false};Microsoft.PowerShell.Management\Test-Path -LiteralPath $p}
try{
 foreach($mode in @('success','module_failure','device_failure','audit_failure','skip')){
  $global:configurationFixture=@{Calls=[Collections.Generic.List[string]]::new();Fail=$(if($mode -eq 'module_failure'){'apply_power_settings.ps1'}elseif($mode -eq 'audit_failure'){'audit_nuc.ps1'}else{''});Skip=$(if($mode -eq 'skip'){'install_drivers.ps1'}else{''});Problem=($mode -eq 'device_failure');Stopped=$false}
  $caught='';try{Invoke-SetupConfiguration -Hardware ([pscustomobject]@{}) -UserName fixture -AutoLogonPassword fixture-secret -DriverPackagePath 'fixture drivers' -ConfirmedBoard NUC8i7HVB -ConfirmationComputer fixture -NonInteractive}catch{$caught=$_.Exception.Message}
  if($caught){Write-Host ('caught='+$caught)}
  $r=Get-Content -LiteralPath (Join-Path $fixture 'Setup-Result.json') -Raw|ConvertFrom-Json
  Assert ($r.Success -eq ($mode -in @('success','skip'))) ('真主流程結果 '+$mode)
  Assert ($global:configurationFixture.Calls.Contains('desktop_icon_layout.ps1') -and $global:configurationFixture.Calls.Contains('audit_nuc.ps1')) ('早期錯誤仍續跑後續與最終檢查 '+$mode)
  Assert ($global:configurationFixture.Stopped -and $global:configurationFixture.PasswordReceived -and $global:configurationFixture.PasswordCleared) ('密碼只傳自動登入且 finally 清空 '+$mode)
  Assert (-not ([IO.File]::ReadAllText((Join-Path $fixture 'Setup-Result.json')).Contains('fixture-secret'))) ('摘要不含密碼 '+$mode)
  if($mode -in @('module_failure','device_failure','audit_failure')){Assert ($caught -like '部分步驟或裝置檢查未完成*') ('失敗保留真例外 '+$mode)}else{Assert (-not $caught) ('成功不誤拋 '+$mode)}
  if($mode -eq 'skip'){Assert ($r.SkippedModules.Count -eq 1 -and -not $global:configurationFixture.Calls.Contains('install_drivers.ps1')) '不適用模組不執行'}else{Assert ($global:configurationFixture.Driver.Path -eq 'fixture drivers' -and $global:configurationFixture.Driver.Board -eq 'NUC8i7HVB' -and $global:configurationFixture.Driver.NonInteractive) '驅動參數完整傳遞'}
  $progress=Get-Content -LiteralPath (Join-Path $fixture 'Setup-Progress.json') -Raw|ConvertFrom-Json
  Assert ($progress.Step -eq 19 -and $progress.Total -eq 19) '19 階段進度保存'
 }
}finally{if($fixture.StartsWith([IO.Path]::GetFullPath($env:TEMP),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $fixture -Recurse -Force}}
