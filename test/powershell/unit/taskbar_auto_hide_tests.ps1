#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
. (Join-Path $root 'modules/taskbar/taskbar_settings_library.ps1')
Assert ($null -ne (Get-Command Invoke-SetupTaskbarAutoHide -ErrorAction SilentlyContinue)) 'Taskbar exposes original-source auto-hide apply and readonly verification'
$script:state=[uint32]2;$script:applyCalls=0;$script:writeCalls=0
function Invoke-SetupTaskbarNativeAutoHide {param([string]$ModuleRoot,[bool]$Apply) $script:applyCalls++;if($Apply){$script:writeCalls++;if(-not $script:discard){$script:state=$script:state -bor 1}};return $script:state}
$r=Invoke-SetupTaskbarAutoHide -ModuleRoot (Join-Path $root 'modules/taskbar')
Assert ($r.AutoHide -and $r.AppBarState -eq 3 -and $script:writeCalls -eq 1) 'Apply enables auto-hide while preserving always-on-top state'
$before=$script:writeCalls;$r=Invoke-SetupTaskbarAutoHide -ModuleRoot (Join-Path $root 'modules/taskbar') -VerifyOnly
Assert ($r.AutoHide -and $script:writeCalls -eq $before) 'VerifyOnly reads the native current-user taskbar without writing'
$script:state=2;$r=Invoke-SetupTaskbarAutoHide -ModuleRoot (Join-Path $root 'modules/taskbar') -VerifyOnly
Assert (-not $r.AutoHide -and $script:writeCalls -eq $before) 'VerifyOnly reports auto-hide disabled rather than silently applying'
$script:discard=$true;$failed=$false
try{Invoke-SetupTaskbarAutoHide -ModuleRoot (Join-Path $root 'modules/taskbar')|Out-Null}catch{$failed=$true}
Assert $failed 'Apply rejects an unchanged native state after setting auto-hide'
function Invoke-SetupTaskbarNativeAutoHide {param([string]$ModuleRoot,[bool]$Apply) throw 'fixture missing interactive taskbar'}
$failed=$false;try{Invoke-SetupTaskbarAutoHide -ModuleRoot (Join-Path $root 'modules/taskbar')|Out-Null}catch{$failed=$true}
Assert $failed 'Missing current-session taskbar remains a failure'