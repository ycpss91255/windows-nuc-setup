#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
function Reject([scriptblock]$Action,[string]$Name){$caught=$false;try{& $Action|Out-Null}catch{$caught=$true};Assert $caught $Name}
$library=Join-Path $root 'core/verification_library.ps1'
Assert (Test-Path $library) '總驗收可由具名函式安全載入'
. (Join-Path $root 'core/hardware.ps1')
. (Join-Path $root 'core/verification.ps1')
. $library
$tokens=$null;$errors=$null
$entry=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'core/verify_only.ps1'),[ref]$tokens,[ref]$errors)
Assert (@($entry.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'Invoke-SetupVerification'},$true)).Count -eq 1) '正式入口呼叫具名驗收彙整一次'
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('verify_aggregate_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
$script:fixtureScripts=Join-Path $fixture 'scripts';[void][IO.Directory]::CreateDirectory($script:fixtureScripts)
foreach($name in @('apply_uac_settings.ps1','audit_nuc.ps1','initialize_ssh_client.ps1','apply_lan_ping_settings.ps1','apply_hosts_sync.ps1','apply_privacy_settings.ps1','apply_display_settings.ps1','apply_theme_settings.ps1','desktop_icon_layout.ps1','apply_pagefile_settings.ps1','apply_copilot_settings.ps1','apply_amd_privacy_settings.ps1','apply_start_menu_settings.ps1','apply_input_method_settings.ps1','apply_terminal_hotkey.ps1','remove_setup_residue.ps1','remove_one_drive.ps1','apply_explorer_settings.ps1')){Copy-Item -LiteralPath (Join-Path $root 'test/powershell/fixtures/verification_module.ps1') -Destination (Join-Path $script:fixtureScripts $name)}
$script:fixtureApps=Join-Path $fixture 'apps.txt';[IO.File]::WriteAllText($script:fixtureApps,'Fixture.App')
function Resolve-NucPath {param($Name) if($Name -eq 'debloat_apps.txt'){return $script:fixtureApps};if($Name -eq 'Verification-Result.json'){return Join-Path $env:ProgramData 'aggregate.json'};return Join-Path $script:fixtureScripts $Name}
function Get-CimInstance {param($ClassName,$Filter) [pscustomobject]@{State=$(if($global:AggregateFixtureMode -eq 'Throw'){'Stopped'}else{'Running'});StartMode='Auto'}}
function Get-SetupSSHFirewallStatus {[pscustomobject]@{Passed=($global:AggregateFixtureMode -ne 'Throw');Detail='fixture'}}
function powercfg.exe {'AC Power Setting Index: 0x00000000'}
function Get-ItemProperty {param($Path,$ErrorAction)
 $values=@{AutoAdminLogon='1';DefaultUserName=$env:USERNAME;SearchOnTaskbarMode=0;AllowNewsAndInterests=0;ShowTaskViewButton=0;Hidden=1;ShowSuperHidden=0}
 foreach($id in @('{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}','{20D04FE0-3AEA-1069-A2D8-08002B30309D}','{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}','{645FF040-5081-101B-9F08-00AA002F954E}')){$values[$id]=0}
 if($global:AggregateFixtureMode -eq 'Throw'){$values.Hidden=0;$values.AutoAdminLogon='0';$values.NUC8FinalizeTaskbar='pending';$values['{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}']=1}
 [pscustomobject]$values
}
function Get-PnpDevice {param([switch]$PresentOnly) if($global:AggregateFixtureMode -eq 'Throw'){[pscustomobject]@{Status='Error'}}}
function Get-ChildItem {param($LiteralPath,[switch]$Force,$ErrorAction) if($global:AggregateFixtureMode -eq 'Throw'){[pscustomobject]@{Attributes=0;Name='fixture.txt'}}}
function Get-AppxPackage {param([switch]$AllUsers) if($global:AggregateFixtureMode -eq 'Throw'){[pscustomobject]@{Name='Fixture.App';PackageUserInformation=@([pscustomobject]@{InstallState='Installed'})}}}
function Get-AppxProvisionedPackage {param([switch]$Online) if($global:AggregateFixtureMode -eq 'Throw'){[pscustomobject]@{DisplayName='Fixture.App'}}}
function Test-SetupDriverPayload {param($Hardware,$DriverPackagePath) if($global:AggregateFixtureMode -eq 'Throw'){throw 'fixture invalid driver'};[pscustomobject]@{Status='Passed'}}
function Test-Path {param($Path,$LiteralPath,$PathType) if($Path -like 'HKLM:*'){return ($global:AggregateFixtureMode -eq 'Throw')};Microsoft.PowerShell.Management\Test-Path @PSBoundParameters}
$previousProgramData=$env:ProgramData
try{
 foreach($mode in @('Pass','False','Throw','Missing','Stale','WrongComputer','WrongUser')){
  $global:AggregateFixtureMode=$mode;$env:ProgramData=Join-Path $fixture $mode
  $data=Join-Path $env:ProgramData 'NUC8-Setup';[void][IO.Directory]::CreateDirectory((Join-Path $data 'WindowsUpdate'))
  [IO.File]::WriteAllText((Join-Path $data 'TaskbarLayout.xml'),'<Layout><TaskbarPinList><DesktopApp DesktopApplicationID="MSEdge" /></TaskbarPinList></Layout>')
  [IO.File]::WriteAllText((Join-Path $data 'WindowsUpdate/WindowsUpdate-Result.json'),'{"Selected":0,"Updates":[],"CompletedAt":"fixture"}')
  $hardware=Get-SetupHardwareProfile -BoardProduct 'NUC8i7HVB' -UICulture zh-TW -DriverPackagePath $fixture
  $id=[guid]::NewGuid().ToString()
  if($mode -eq 'Pass'){Invoke-SetupVerification -Hardware $hardware -DriverPackagePath $fixture -VerificationRunId $id|Out-Null}
  else{Reject {Invoke-SetupVerification -Hardware $hardware -DriverPackagePath $fixture -VerificationRunId $id} ('安全彙整拒絕 '+$mode)}
  $result=Get-Content (Resolve-NucPath 'Verification-Result.json') -Raw|ConvertFrom-Json
  Assert ($result.VerificationRunId -eq $id -and $result.UserSID -eq [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) ('保留本輪ID及動態身分 '+$mode)
  Assert ($result.Passed -eq ($mode -eq 'Pass')) ('總結果不假通過 '+$mode)
  Assert (@($result.Checks|Where-Object Name -eq '非必要資料分享政策').Count -eq 1) ('保留隱私檢查 '+$mode)
  $expected=@{Throw='fixture submodule failed';Missing='本輪驗證未產生結果';Stale='驗證結果不是本輪產生';WrongComputer='電腦或使用者不符';WrongUser='電腦或使用者不符'}
  if($expected.ContainsKey($mode)){$detail=($result.Checks|Where-Object Name -eq '非必要資料分享政策').Detail;Assert ($detail.Contains($expected[$mode])) ('失敗原因確實來自預期本輪拒絕 '+$mode)}
 }
 $global:AggregateFixtureMode='Pass'
 $generic=Get-SetupHardwareProfile -BoardProduct 'Other PC' -UICulture en-US
 Invoke-SetupVerification -Hardware $generic -VerificationRunId ([guid]::NewGuid().ToString())|Out-Null
 $result=Get-Content (Resolve-NucPath 'Verification-Result.json') -Raw|ConvertFrom-Json
 Assert ($result.Passed -and $result.SkippedCount -eq 3) '通用英文電腦明確略過NUC驅動AMD與中文座標'
 Assert (@($result.Checks|Where-Object {$_.Status -eq 'Skipped' -and $null -eq $_.Passed}).Count -eq 3) '略過不可冒充Passed'
}finally{$env:ProgramData=$previousProgramData;Remove-Variable AggregateFixtureMode -Scope Global -ErrorAction SilentlyContinue}
Write-Host 'ALL PASS: verification aggregator source tests; OS boundaries mocked'
