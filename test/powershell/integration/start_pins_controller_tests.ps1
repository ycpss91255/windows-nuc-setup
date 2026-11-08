#Requires -Version 5.1
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $repo 'modules/start_menu/start_pins_policy_library.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$source=[IO.File]::ReadAllText((Join-Path $repo 'core/configure_nuc.ps1'));$t=$null;$e=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$t,[ref]$e)
$main=$ast.EndBlock.Statements|Where-Object {$_ -is [Management.Automation.Language.TryStatementAst]}|Select-Object -First 1
$fixture=Join-Path $env:TEMP ('start_controller_'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory $fixture
$names=@([regex]::Matches($source,"File='([^']+\.ps1)'" )|ForEach-Object {$_.Groups[1].Value})+@('apply_uac_settings.ps1','apply_autologon_settings.ps1','audit_nuc.ps1')
foreach($name in $names){[IO.File]::WriteAllText((Join-Path $fixture $name),'$global:startTestCalls.Add([IO.Path]::GetFileName($PSCommandPath))|Out-Null')}
[IO.File]::WriteAllText((Join-Path $fixture 'apply_start_menu_settings.ps1'),@'
param([switch]$ApplyPolicy,[switch]$NonInteractive)
$global:startTestCalls.Add('apply_start_menu_settings.ps1')|Out-Null
if($ApplyPolicy){$global:startTestLate++;if($global:startTestCalls.IndexOf('desktop_icon_layout.ps1') -lt 0 -or $global:startTestCalls.IndexOf('audit_nuc.ps1') -lt 0){throw 'late apply preceded final stages'};if(-not(Test-Path (Join-Path $fixture 'Setup-Result.json'))){throw 'no persisted pending summary before risky apply'};[pscustomobject]@{Success=$false;Status='PendingSignIn';PinCount=1}}
else{[pscustomobject]@{Success=$false;Status='LegacyPendingApply';PinCount=1}}
'@)
function Resolve-NucPath {param($Name) Join-Path $fixture $Name}
function Get-SetupModuleDecision {param($Module,$Hardware) [pscustomobject]@{Applicable=$true}}
function Get-ItemProperty {param($Path) [pscustomobject]@{DefaultUserName='fixture';AutoAdminLogon='1'}}
function Get-PnpDevice {param([switch]$PresentOnly) if($script:problem){[pscustomobject]@{Status='Error'}}}
function Stop-Transcript {}
function Test-Path {param($LiteralPath,$Path,$PathType) $p=if($LiteralPath){$LiteralPath}else{$Path};if($p -like 'HKLM:*'){return $false};Microsoft.PowerShell.Management\Test-Path -LiteralPath $p}
foreach($case in @('normal','noninteractive','device_error')){
 $global:startTestCalls=New-Object 'Collections.Generic.List[string]';$global:startTestLate=0;$script:problem=$case -eq 'device_error';$NonInteractive=$case -eq 'noninteractive';$hardware=[pscustomobject]@{};$skippedModules=@();$AutoLogonPassword=$null;$UserName='fixture'
 $caught='';try{& ([scriptblock]::Create($main.Extent.Text))}catch{$caught=$_.Exception.Message}
 if($caught){Write-Host ('caught='+$caught)}
 $r=Get-Content (Join-Path $fixture 'Setup-Result.json') -Raw|ConvertFrom-Json
 Assert (-not $r.Success -and @($r.PendingModules).Count -eq 1 -and $r.PendingModules[0].Module -eq 'apply_start_menu_settings.ps1') ('controller persists pending without false success '+$case)
 if($case -eq 'normal'){Assert ($global:startTestLate -eq 1 -and $r.PendingModules[0].Status -eq 'PendingSignIn' -and $r.StageErrors.Count -eq 0) 'late apply after all stages keeps pending separate from errors'}else{Assert ($global:startTestLate -eq 0) ('no late install '+$case)}
}
