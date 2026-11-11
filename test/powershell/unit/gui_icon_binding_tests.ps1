#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
. (Join-Path $root 'core/gui_stage_library.ps1')
$temp=Join-Path ([IO.Path]::GetTempPath()) ('gui_icon_binding_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
$run=[guid]::NewGuid().ToString('D');$paths=Get-SetupGuiRunPaths -CommonDataRoot $temp -Role Icons -RunId $run;[void][IO.Directory]::CreateDirectory($paths.DataRoot)
$script:context=[pscustomobject]@{Schema=1;Role='Icons';RunId=$run;Computer='fixture';UserSID='S-1-5-21-1-2-3-1001';DesktopSession=4;VerifyOnly=$false;IconMode='Save'}
$stage=[pscustomobject]@{CodeRoot=$paths.CodeRoot;DataRoot=$paths.DataRoot;CommonDataRoot=$temp;Context=$script:context}
function Read-SetupGuiContext {param($CodeRoot,$CommonDataRoot,$Role,$RunId) if($CodeRoot -cne $paths.CodeRoot -or $CommonDataRoot -cne $temp -or $Role -cne 'Icons' -or $RunId -cne $run){throw 'wrong fixture bound context'};$script:context}
function Assert-SetupGuiProtectedPath {param($Path,[switch]$Directory,$UserSid) if(-not $Path.StartsWith($temp) -or -not(Test-Path -LiteralPath $Path)){throw 'outside fixture protected path'}}
Write-SetupGuiResult -DataRoot $paths.DataRoot -Context $script:context -Result @{Success=$true;Mode='Save'}
$r=Read-SetupGuiResult $stage
Assert ($r.Success -and $r.Mode -ceq 'Save') 'bound Icons result accepts exactly its requested finite mode'
foreach($mode in @('Load','Verify','ExecuteAnything','')){
 Write-SetupGuiResult -DataRoot $paths.DataRoot -Context $script:context -Result @{Success=$true;Mode=$mode}
 $failure='';try{Read-SetupGuiResult $stage|Out-Null}catch{$failure=$_.Exception.Message}
 Assert ($failure.Contains('圖示模式')) ('same run identity cannot authorize wrong Icons result mode: '+$mode)
}