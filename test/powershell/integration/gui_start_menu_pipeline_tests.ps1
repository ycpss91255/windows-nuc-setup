#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
. (Join-Path $root 'core/gui_stage_library.ps1')
$files=@(Get-SetupGuiStageFiles Start)
Assert ($files.Count -eq 8 -and $files -contains 'modules/start_menu/start_menu_settings_library.ps1' -and $files -contains 'modules/start_menu/assets/empty_start.ppkg' -and $files -contains 'modules/start_menu/assets/provenance.json') 'Start private manifest pins exact leaf helper and original provisioning assets'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('gui_start_pipeline_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
$script:session=4;$script:installed=$false;$script:installs=0;$script:asked=0;$script:pins=1;$script:writes=0;$script:values=@{CurrentBuildNumber='22631';UBR=9999;NoStartMenuMorePrograms=1}
function Get-SetupGuiIdentity {[pscustomobject]@{CommonDataRoot=$temp;UserSID='S-1-5-21-1-2-3-1001';SessionId=$script:session;Computer='fixture'}}
function Get-SetupGuiDesktopSession {param($Scope) 4}
function Assert-SetupGuiAncestors {param($CommonDataRoot) if($CommonDataRoot -ne $temp){throw 'wrong fixture parent'}}
function New-SetupGuiProtectedDirectory {param($Path,$UserSid) if(-not $Path.StartsWith($temp)){throw 'outside TEMP'};[void][IO.Directory]::CreateDirectory($Path)}
function Assert-SetupGuiProtectedPath {param($Path,[switch]$Directory,$UserSid) if(-not $Path.StartsWith($temp) -or -not(Microsoft.PowerShell.Management\Test-Path -LiteralPath $Path)){throw 'outside protected fixture'}}
function Invoke-SetupGuiLocalWorker {param($Stage,$Scope) Invoke-SetupGuiWorker -CodeRoot $Stage.CodeRoot -Role $Stage.Context.Role -RunId $Stage.Context.RunId|Out-Null}
function Test-Path {param($Path,$LiteralPath,$PathType) if($Path -like 'HKCU:*'){return $true};if($LiteralPath -like '*PolicyDefinitions*'){return $false};Microsoft.PowerShell.Management\Test-Path @PSBoundParameters}
function New-ItemProperty {param($Path,$Name,$Value,$PropertyType,[switch]$Force) if($Path -notlike 'HKCU:*'){throw 'unexpected registry mutation'};$script:values[$Name]=$Value;$script:writes++}
function Get-ItemProperty {param($Path,$LiteralPath,$ErrorAction) if($Path -and $Path -notlike 'HKCU:*'){throw 'unexpected registry read'};if($LiteralPath -and $LiteralPath -ne 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'){throw 'unexpected version read'};[pscustomobject]$script:values}
function Get-ProvisioningPackage {param($PackagePath,$LogsDirectoryPath,[switch]$AllInstalledPackages,$ErrorAction) if($PackagePath -or $script:installed){[pscustomobject]@{PackageID='73c18f23-529e-4379-a458-4c9b3a8d5b92';PackageName='windows_setup_empty_start';Version='1.0';Rank=0;OwnerType=5000;IsInstalled=$script:installed}}}
function Install-ProvisioningPackage {param($PackagePath,[switch]$QuietInstall,$ErrorAction) if($PackagePath -notlike ($temp+'*\modules\start_menu\assets\empty_start.ppkg')){throw 'unexpected provisioning path'};$script:installed=$true;$script:installs++}
function Export-StartLayout {param($Path,$ErrorAction) if(-not $Path.StartsWith($temp)){throw 'outside TEMP export'};[IO.File]::WriteAllText($Path,$(if($script:pins -eq 0){'{"pinnedList":[]}'}else{'{"pinnedList":[{"desktopAppId":"Fixture"}]}'}))}
function Read-Host {param($Prompt) $script:asked++;'YES'}
$r=Invoke-SetupGuiRole -PackageRoot $root -Role Start
Assert (-not $r.Success -and $r.Status -ceq 'LegacyPendingApply' -and $script:installs -eq 0 -and $script:asked -eq 0) 'ordinary Start stage never installs policy early and returns honest bound pending result'
$r=Invoke-SetupGuiRole -PackageRoot $root -Role Start -ApplyPolicy -NonInteractive
Assert (-not $r.Success -and $r.Status -ceq 'LegacyPendingApply' -and $script:installs -eq 0 -and $script:asked -eq 0) 'noninteractive explicit policy remains pending without hidden prompt or installation'
$r=Invoke-SetupGuiRole -PackageRoot $root -Role Start -ApplyPolicy
Assert (-not $r.Success -and $r.Status -ceq 'PendingSignIn' -and $script:installs -eq 1 -and $script:asked -eq 1) 'late explicit interactive ApplyPolicy uses original asset algorithm once and remains pending until native empty export'
$script:pins=0;$before=$script:writes;$r=Invoke-SetupGuiFreshVerification -PackageRoot $root -Role Start
Assert ($r.Success -and $r.Status -ceq 'Confirmed' -and $r.VerifyOnly -and $script:writes -eq $before -and $script:installs -eq 1) 'fresh Start verifies real export through private result without reapplying settings'
$paths=Get-SetupGuiRunPaths -CommonDataRoot $temp -Role Start -RunId $r.RunId;$context=Read-SetupGuiContext -CodeRoot $paths.CodeRoot -CommonDataRoot $temp -Role Start -RunId $r.RunId
Assert ($context.ApplyPolicy -is [bool] -and -not $context.ApplyPolicy -and $context.NonInteractive -is [bool]) 'Start context carries only typed finite policy switches'
$original=[IO.File]::ReadAllText((Join-Path $paths.CodeRoot 'context.json'));$bad=$original|ConvertFrom-Json;$bad.ApplyPolicy='true';[IO.File]::WriteAllText((Join-Path $paths.CodeRoot 'context.json'),($bad|ConvertTo-Json -Depth 8));$failure=''
try{Read-SetupGuiContext -CodeRoot $paths.CodeRoot -CommonDataRoot $temp -Role Start -RunId $r.RunId|Out-Null}catch{$failure=$_.Exception.Message}
Assert ($failure.Contains('開始選單模式')) 'text masquerading as policy bool is rejected before worker import'
[IO.File]::WriteAllText((Join-Path $paths.CodeRoot 'context.json'),$original)
Assert (-not (Test-Path -LiteralPath (Join-Path $temp 'NUC8-Setup'))) 'Start never creates public fixed worker or result authority'