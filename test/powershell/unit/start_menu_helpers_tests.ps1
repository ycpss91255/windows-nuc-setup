#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$library=Join-Path $root 'modules/start_menu/start_menu_settings_library.ps1'
Assert (Test-Path -LiteralPath $library) 'Start has a named original-source leaf without executing public administrator entry'
. $library
$temp=Join-Path ([IO.Path]::GetTempPath()) ('start_menu_leaf_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
$script:createdKeys=@();$script:missingKeys=$true;$script:writes=0;$script:status='Confirmed';$script:appList=1;$script:received=$null
function Test-Path {param($Path) if($Path -notlike 'HKCU:*'){throw 'unexpected Start path query'};(-not $script:missingKeys)}
function New-Item {param($Path,[switch]$Force) if($Path -notlike 'HKCU:*' -or -not $Force){throw 'unexpected Start key creation'};$script:createdKeys+=@($Path)}
function New-ItemProperty {param($Path,$Name,$PropertyType,$Value,[switch]$Force) if($Path -notlike 'HKCU:*' -or $PropertyType -ne 'DWord' -or -not $Force){throw 'unexpected Start write'};$script:writes++}
function Get-ItemProperty {param($Path) if($Path -ne 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer'){throw 'unexpected Start read'};[pscustomobject]@{NoStartMenuMorePrograms=$script:appList}}
function Invoke-StartPinsConfiguration {param($AssetRoot,$OutputRoot,[switch]$VerifyOnly,[switch]$ApplyPolicy,[switch]$NonInteractive) $script:received=[pscustomobject]@{Asset=$AssetRoot;Output=$OutputRoot;Verify=[bool]$VerifyOnly;Apply=[bool]$ApplyPolicy;NonInteractive=[bool]$NonInteractive};[ordered]@{Success=($script:status -eq 'Confirmed');Status=$script:status;PinCount=0}}
$r=Invoke-SetupStartMenuSettings -ModuleRoot (Join-Path $root 'modules/start_menu') -OutputRoot $temp -ApplyPolicy -NonInteractive
$script:missingKeys=$false
Assert ($script:createdKeys.Count -eq 2) 'first-use Start creates both missing per-user policy keys through mocked registry only'
Assert ($r.Success -and $r.Status -eq 'Confirmed' -and $script:writes -eq 5 -and $script:received.Apply -and $script:received.NonInteractive -and $script:received.Asset -eq (Join-Path $root 'modules/start_menu/assets')) 'Start preserves five privacy/list policies and finite policy flags'
$before=$script:writes;$r=Invoke-SetupStartMenuSettings -ModuleRoot (Join-Path $root 'modules/start_menu') -OutputRoot $temp -VerifyOnly
Assert ($r.Success -and $script:writes -eq $before -and $script:received.Verify) 'Start VerifyOnly reads completion without changing settings'
foreach($status in @('LegacyPendingApply','PendingSignIn')){$script:status=$status;$r=Invoke-SetupStartMenuSettings -ModuleRoot (Join-Path $root 'modules/start_menu') -OutputRoot $temp -NonInteractive;Assert (-not $r.Success -and $r.Status -eq $status) ('Start retains honest pending status: '+$status)}
$script:status='Confirmed';$script:appList=0;$r=Invoke-SetupStartMenuSettings -ModuleRoot (Join-Path $root 'modules/start_menu') -OutputRoot $temp -VerifyOnly
Assert (-not $r.Success -and $r.Status -eq 'Failed' -and $r.Error) 'native pin export cannot hide missing application-list policy'