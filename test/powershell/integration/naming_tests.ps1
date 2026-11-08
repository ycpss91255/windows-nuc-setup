#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
. (Join-Path $root 'core/paths.ps1')
. (Join-Path $root 'core/after_restart_library.ps1')
Assert ([bool](Get-Command Invoke-SetupAfterRestart -ErrorAction SilentlyContinue)) '續跑具名正式來源可安全載入'
$fixture=Join-Path $env:TEMP ('names portable 驗證_'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'core'));[void][IO.Directory]::CreateDirectory((Join-Path $fixture 'reports'))
$script:NucPackageRoot=$fixture
Copy-Item -LiteralPath (Join-Path $root 'core/configuration_library.ps1') -Destination (Join-Path $fixture 'core/configuration_library.ps1')
$marker=Join-Path $fixture 'invoked.txt'
$global:NamingFixture=@{Marker=$marker;VerificationPath=(Resolve-NucPath 'Verification-Result.json');Calls=[Collections.Generic.List[string]]::new()}
foreach($file in @('install_windows_updates.ps1','apply_debloat.ps1','apply_copilot_settings.ps1','remove_setup_residue.ps1')){
 $path=Resolve-NucPath $file;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
 [IO.File]::WriteAllText($path,@'
$name=[IO.Path]::GetFileName($PSCommandPath);$global:NamingFixture.Calls.Add($name)
if($name -eq 'apply_debloat.ps1'){[IO.File]::WriteAllText($global:NamingFixture.Marker,'called')}
'@,[Text.UTF8Encoding]::new($true))
}
$path=Resolve-NucPath 'verify_only.ps1'
[IO.File]::WriteAllText($path,@'
param($VerificationRunId)
@{VerificationRunId=$VerificationRunId;Computer=$env:COMPUTERNAME;UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;Passed=$true;Checks=@()}|ConvertTo-Json|Set-Content -LiteralPath $global:NamingFixture.VerificationPath -Encoding UTF8
'@,[Text.UTF8Encoding]::new($true))
Assert ((Resolve-NucPath 'Apply-Debloat.ps1') -eq (Join-Path $fixture 'modules/debloat/apply_debloat.ps1')) 'legacy source alias resolves to dynamic physical filename'
Assert ((Resolve-NucModuleName 'Apply-Debloat.ps1') -ceq 'apply_debloat.ps1') 'legacy failed module id normalizes before allowlist'
Assert ((Resolve-NucPath 'Setup-Result.json') -eq (Join-Path $fixture 'reports/Setup-Result.json')) 'existing per-machine result filename remains compatible'
function Get-SetupModuleDecision {param($Module,$Hardware) [pscustomobject]@{Applicable=($Module -notin @('install_drivers.ps1','desktop_icon_layout.ps1'));Reason='fixture optional skipped'}}
function Get-ItemProperty {param($Path,$ErrorAction) [pscustomobject]@{StartLayoutFile=''}}
$record=[pscustomobject]@{Computer=$env:COMPUTERNAME;UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value;FailedModules=@('Apply-Debloat.ps1');StageErrors=@();Success=$false;PendingModules=@()}
try{
 $record|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Resolve-NucPath 'Setup-Result.json') -Encoding UTF8
 Invoke-SetupAfterRestart -Hardware @{} -DriverPackagePath ''
 Assert ((Test-Path $marker) -and [IO.File]::ReadAllText($marker) -eq 'called' -and @($global:NamingFixture.Calls|Where-Object {$_ -eq 'apply_debloat.ps1'}).Count -eq 2) 'actual named continuation retries legacy module plus its normal cleanup'
 Assert ($global:NamingFixture.Calls[0] -eq 'install_windows_updates.ps1' -and $global:NamingFixture.Calls[1] -eq 'apply_debloat.ps1') 'legacy retry uses actual dynamic resolver after Windows Update'
 foreach($mode in @('foreign_sid','unknown_module')){
  [IO.File]::WriteAllText($marker,'unchanged');$global:NamingFixture.Calls.Clear()
  $record.UserSID=if($mode -eq 'foreign_sid'){'different-owner'}else{[Security.Principal.WindowsIdentity]::GetCurrent().User.Value}
  $record.FailedModules=if($mode -eq 'unknown_module'){@('Apply-Debloat.ps1','unregistered.ps1')}else{@('Apply-Debloat.ps1')}
  $record|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Resolve-NucPath 'Setup-Result.json') -Encoding UTF8
  $caught='';try{Invoke-SetupAfterRestart -Hardware @{} -DriverPackagePath ''}catch{$caught=$_.Exception.Message}
  Assert ($caught -like $(if($mode -eq 'foreign_sid'){'續跑紀錄不是*'}else{'未知的失敗模組*'})) ('真入口在副作用前拒絕 '+$mode)
  Assert ($global:NamingFixture.Calls.Count -eq 0 -and [IO.File]::ReadAllText($marker) -eq 'unchanged') ('未知模組與foreign SID都在WU前拒絕且不碰marker '+$mode)
 }
}finally{Remove-Variable NamingFixture -Scope Global -ErrorAction SilentlyContinue}
