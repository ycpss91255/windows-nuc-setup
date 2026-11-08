#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$script:count=0
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name};$script:count++}
. (Join-Path $root 'modules/explorer/explorer_settings_library.ps1')
$key='HKCU:\Software\Microsoft\Windows\CurrentVersion\explorer\Advanced'
$script:values=@{Hidden=0;ShowSuperHidden=0;HideFileExt=1};$script:writes=@();$script:created=0;$script:keyExists=$false;$script:options=0;$script:notified=0;$script:shells=0;$script:refreshed=0;$script:warnings=0;$script:throwOptions=$false;$script:requestedApply=@()
function Test-Path {param($Path,$LiteralPath) if($Path -ne $key){throw 'unexpected registry path'};$script:keyExists}
function New-Item {param($Path,[switch]$Force) if($Path -ne $key){throw 'unexpected registry creation'};$script:keyExists=$true;$script:created++}
function Set-ItemProperty {param($Path,$Name,$Value) if($Path -ne $key -or $Name -notin @('Hidden','ShowSuperHidden','HideFileExt')){throw 'unexpected registry write'};$script:values[$Name]=$Value;$script:writes+=@($Name)}
function Get-ItemProperty {param($Path) if($Path -ne $key){throw 'unexpected registry read'};[pscustomobject]$script:values}
function Invoke-SetupExplorerNotification {$script:notified++}
function Get-SetupExplorerShellOptions {param($ModuleRoot,[switch]$Apply) $script:requestedApply+=@([bool]$Apply);if($script:throwOptions){throw 'native fixture failure'};if($Apply){$script:options=3};$script:options}
function New-SetupExplorerShell {$script:shells++;$s=[pscustomobject]@{};$s|Add-Member ScriptMethod Windows {,@($script:windows)};return $s}
function Write-Warning {param($Message) $script:warnings++}
$good=[pscustomobject]@{FullName='C:\fixture\explorer.exe'};$good|Add-Member ScriptMethod Refresh {$script:refreshed++}
$other=[pscustomobject]@{FullName='C:\fixture\other.exe'};$other|Add-Member ScriptMethod Refresh {throw 'must not refresh unrelated app'}
$bad=[pscustomobject]@{FullName='explorer.exe'};$bad|Add-Member ScriptMethod Refresh {throw 'fixture refresh failure'}
$script:windows=@($good,$other,$bad)
$result=Invoke-SetupExplorerSettings -ModuleRoot (Join-Path $root 'modules/explorer') -VerifyOnly
Assert (-not $result.Success -and $script:writes.Count -eq 0 -and $script:notified -eq 0 -and $script:shells -eq 0 -and -not $script:requestedApply[0]) 'Explorer VerifyOnly reads current shell and registry without any writes or refresh'
$result=Invoke-SetupExplorerSettings -ModuleRoot (Join-Path $root 'modules/explorer')
Assert ($result.Success -and $result.ShowFileExtensions -and $result.ShowHiddenFiles -and $result.HideProtectedSystemFiles -and $result.ShellShowsHidden -and $result.ShellShowsExtensions) 'Explorer applies and verifies all user-visible state'
Assert ($script:created -eq 1 -and ($script:writes -join ',') -ceq 'Hidden,ShowSuperHidden,HideFileExt' -and $script:values.Hidden -eq 1 -and $script:values.ShowSuperHidden -eq 0 -and $script:values.HideFileExt -eq 0) 'Explorer writes only three approved dynamic-current-user registry values'
Assert ($script:notified -eq 1 -and $script:refreshed -eq 1 -and $script:warnings -eq 1) 'Explorer refreshes only matching windows and reports isolated refresh failure'
$before=$script:writes.Count;$result=Invoke-SetupExplorerSettings -ModuleRoot (Join-Path $root 'modules/explorer') -VerifyOnly
Assert ($result.Success -and $script:writes.Count -eq $before -and $script:notified -eq 1) 'verified Explorer read does not reapply configuration'
$script:options=1;$result=Invoke-SetupExplorerSettings -ModuleRoot (Join-Path $root 'modules/explorer') -VerifyOnly
Assert (-not $result.Success -and -not $result.ShellShowsExtensions -and $result.Error) 'registry alone cannot falsely prove live extension visibility'
$script:options=3;$script:values.Hidden=0;$result=Invoke-SetupExplorerSettings -ModuleRoot (Join-Path $root 'modules/explorer') -VerifyOnly
Assert (-not $result.Success -and -not $result.ShowHiddenFiles) 'live shell alone cannot falsely prove registry hidden-file preference'
$script:throwOptions=$true;$failure=$null;try{Invoke-SetupExplorerSettings -ModuleRoot (Join-Path $root 'modules/explorer') -VerifyOnly|Out-Null}catch{$failure=$_}
Assert ($null -ne $failure -and $failure.Exception.Message -eq 'native fixture failure') 'Explorer preserves native failure for protected worker reporting'
Write-Host ('ALL PASS: '+$script:count+' Explorer original-source assertions; registry native API and COM fully mocked')