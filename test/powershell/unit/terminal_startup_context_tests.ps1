#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/terminal/terminal_hotkey_library.ps1')
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('terminal_missing_startup_'+[guid]::NewGuid().ToString('N'))
$script:verified=Join-Path $temp 'redirected existing startup'
$script:unverified=Join-Path $temp 'redirected uncreated startup'
$script:appdata=Join-Path $temp 'dynamic roaming'
function Get-SetupTerminalKnownFolder {
 param([Environment+SpecialFolder]$Folder,[Environment+SpecialFolderOption]$Option=[Environment+SpecialFolderOption]::None)
 if($Folder -eq [Environment+SpecialFolder]::ApplicationData){return $script:appdata}
 if($Option -eq [Environment+SpecialFolderOption]::DoNotVerify){return $script:unverified}
 return $script:verified
}
$context=Get-SetupTerminalContext
Assert ($context.Startup -ceq (Join-Path $script:verified 'Terminal Hotkey.lnk')) 'existing redirected Startup takes precedence'
$script:verified=''
$context=$null;$failure=$null;try{$context=Get-SetupTerminalContext}catch{$failure=$_}
Assert ($null -eq $failure -and $context.Startup -ceq (Join-Path $script:unverified 'Terminal Hotkey.lnk')) 'empty verified Startup resolves uncreated redirected KnownFolder without Join-Path failure'
$script:unverified=''
$context=Get-SetupTerminalContext
Assert ($context.Startup -ceq (Join-Path $script:appdata 'Microsoft/Windows/Start Menu/Programs/Startup/Terminal Hotkey.lnk')) 'absent Startup registration falls back to current dynamic ApplicationData'
Assert (-not (Test-Path -LiteralPath $temp)) 'context getter never creates profile directories'
$script:appdata=''
$failure=$null;try{Get-SetupTerminalContext|Out-Null}catch{$failure=$_}
Assert ($null -ne $failure -and $failure.Exception -isnot [Management.Automation.ParameterBindingException]) 'missing all profile roots fails explicitly rather than using a relative startup path'
