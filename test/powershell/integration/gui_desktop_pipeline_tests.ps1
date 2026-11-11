#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
. (Join-Path $root 'core/gui_stage_library.ps1')
$files=@(Get-SetupGuiStageFiles Desktop)
Assert (($files -join '|') -ceq 'core/gui_stage_library.ps1|core/gui_worker.ps1|modules/desktop/desktop_settings_library.ps1|modules/desktop/desktop_safety.ps1') 'Desktop private role has exact fixed executable source including original source guard'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('gui_desktop_pipeline_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
$script:desktop=Join-Path $temp 'desktop';[void][IO.Directory]::CreateDirectory($script:desktop)
[IO.File]::WriteAllText((Join-Path $script:desktop 'ordinary.txt'),'delete')
Add-Type -TypeDefinition 'using System;public static class NUC8DesktopRefresh{public static int Calls;public static void SHChangeNotify(int e,uint f,IntPtr a,IntPtr b){Calls++;}}'
function Get-SetupGuiIdentity {[pscustomobject]@{CommonDataRoot=$temp;UserSID='S-1-5-21-1-2-3-1001';SessionId=4;Computer='fixture'}}
function Get-SetupDesktopRoots {@($script:desktop)}
function Get-SetupGuiDesktopSession {param($Scope) 4}
function Assert-SetupGuiAncestors {param($CommonDataRoot) if($CommonDataRoot -ne $temp){throw 'wrong fixture parent'}}
function New-SetupGuiProtectedDirectory {param($Path,$UserSid) if(-not $Path.StartsWith($temp)){throw 'outside TEMP'};[void][IO.Directory]::CreateDirectory($Path)}
function Assert-SetupGuiProtectedPath {param($Path,[switch]$Directory,$UserSid) if(-not $Path.StartsWith($temp) -or -not(Microsoft.PowerShell.Management\Test-Path -LiteralPath $Path)){throw 'outside protected fixture'}}
function Invoke-SetupGuiLocalWorker {param($Stage,$Scope) Invoke-SetupGuiWorker -CodeRoot $Stage.CodeRoot -Role $Stage.Context.Role -RunId $Stage.Context.RunId|Out-Null}
function Test-Path {param($Path,$LiteralPath,$PathType) if($Path -like 'HK*'){return $true};Microsoft.PowerShell.Management\Test-Path @PSBoundParameters}
$script:writes=0
function New-ItemProperty {param($Path,$Name,$Value,$PropertyType,[switch]$Force) if($Path -notlike 'HK*'){throw 'unexpected registry write'};$script:writes++}
$r=Invoke-SetupGuiRole -PackageRoot $root -Role Desktop
Assert ($r.Success -and $r.Role -ceq 'Desktop' -and $r.SessionId -eq 4 -and $script:writes -eq 19 -and -not(Test-Path -LiteralPath (Join-Path $script:desktop 'ordinary.txt'))) 'actual private Desktop producer worker leaf and bound reader clean only fixture desktop'
$paths=Get-SetupGuiRunPaths -CommonDataRoot $temp -Role Desktop -RunId $r.RunId
$context=Read-SetupGuiContext -CodeRoot $paths.CodeRoot -CommonDataRoot $temp -Role Desktop -RunId $r.RunId
Assert ($context.SourcePackageRoot -ceq $root -and $context.SourcePackageRoot -cne $paths.CodeRoot) 'protected Desktop context binds original package root rather than safe-looking staged code root'
$before=$script:writes;$refresh=[NUC8DesktopRefresh]::Calls
$r=Invoke-SetupGuiFreshVerification -PackageRoot $root -Role Desktop
Assert ($r.Success -and $r.VerifyOnly -and $script:writes -eq $before -and [NUC8DesktopRefresh]::Calls -eq $refresh) 'Desktop fresh verification produces bound current data without reapplying preferences'
$script:desktop=$root;$failure=''
try{Invoke-SetupGuiRole -PackageRoot $root -Role Desktop|Out-Null}catch{$failure=$_.Exception.Message}
Assert ($failure.Contains('工具包不可位於桌面') -and $script:writes -eq $before) 'fixed worker rechecks actual original source location against current desktop before any cleanup or write'
Assert (-not (Test-Path -LiteralPath (Join-Path $temp 'NUC8-Setup'))) 'Desktop never trusts legacy world-writable result or worker'