#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
. (Join-Path $root 'core/gui_stage_library.ps1')
$files=@(Get-SetupGuiStageFiles Icons)
Assert (($files -join '|') -ceq 'core/gui_stage_library.ps1|core/gui_worker.ps1|modules/desktop/icons_settings_library.ps1|modules/desktop/native/desktop_icons.cs') 'Icons approved manifest never includes mutable desktop_layout input'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('gui_icons_pipeline_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($temp)
$package=Join-Path $temp 'package';foreach($file in $files){$to=Join-Path $package $file;[void][IO.Directory]::CreateDirectory((Split-Path $to));Copy-Item -LiteralPath (Join-Path $root $file) -Destination $to}
Add-Type -TypeDefinition 'using System;using System.Collections.Generic;namespace NUC8Icons{public static class Desktop{public static Queue<object> Frames=new Queue<object>();public static int Moves;public static object Capture(){return Frames.Dequeue();}public static void Position(int i,int x,int y){Moves++;}}}'
function Frame {$i=0;[pscustomobject]@{Width=1920;Height=1080;Icons=@(foreach($n in @('控制台','本機','網路','資源回收筒')){[pscustomobject]@{Name=$n;Index=$i;X=($i*100);Y=10};$i++})}}
$reference=Join-Path $package 'modules/desktop/desktop_layout.json';[IO.File]::WriteAllText($reference,((Frame)|ConvertTo-Json -Depth 5))
$script:ids=@('{5399E694-6CE5-4D6C-8FCE-1D8870FDCBA0}','{20D04FE0-3AEA-1069-A2D8-08002B30309D}','{F02C1A0D-BE21-4350-88B0-7367FC96EF3C}','{645FF040-5081-101B-9F08-00AA002F954E}')
function New-Object {param($TypeName,$ComObject,$ArgumentList) if($ComObject){if($ComObject -ne 'Shell.Application'){throw 'unexpected COM'};$d=[pscustomobject]@{};$d|Add-Member ScriptMethod ParseName {param($path) $index=[array]::IndexOf($script:ids,($path.Substring(2)));if($index -lt 0){throw 'unexpected CLSID'};[pscustomobject]@{Name=@('控制台','本機','網路','資源回收筒')[$index]}};$o=[pscustomobject]@{Desktop=$d};$o|Add-Member ScriptMethod NameSpace {param($id) if($id -ne 0){throw 'unexpected namespace'};$this.Desktop};return $o};Microsoft.PowerShell.Utility\New-Object @PSBoundParameters}
function Get-SetupGuiIdentity {[pscustomobject]@{CommonDataRoot=$temp;UserSID='S-1-5-21-1-2-3-1001';SessionId=4;Computer='fixture'}}
function Get-SetupGuiDesktopSession {param($Scope) 4}
function Assert-SetupGuiAncestors {param($CommonDataRoot) if($CommonDataRoot -ne $temp){throw 'wrong fixture parent'}}
function New-SetupGuiProtectedDirectory {param($Path,$UserSid) if(-not $Path.StartsWith($temp)){throw 'outside TEMP'};[void][IO.Directory]::CreateDirectory($Path)}
function Assert-SetupGuiProtectedPath {param($Path,[switch]$Directory,$UserSid) if(-not $Path.StartsWith($temp) -or -not(Test-Path -LiteralPath $Path)){throw 'outside protected fixture'}}
function Invoke-SetupGuiLocalWorker {param($Stage,$Scope) Invoke-SetupGuiWorker -CodeRoot $Stage.CodeRoot -Role $Stage.Context.Role -RunId $Stage.Context.RunId|Out-Null}
function Get-ItemProperty {param($Path,$ErrorAction) [pscustomobject]@{FFlags=3}}
function Set-ItemProperty {param($Path,$Name,$Value) if($Name -ne 'FFlags' -or $Value -ne 2){throw 'unexpected write'}}
function Start-Sleep {param($Milliseconds)}
foreach($mode in @('Load','Verify','Save')){
 [NUC8Icons.Desktop]::Frames.Enqueue((Frame));if($mode -ne 'Save'){[NUC8Icons.Desktop]::Frames.Enqueue((Frame))}
 $beforeMoves=[NUC8Icons.Desktop]::Moves
 $r=if($mode -eq 'Verify'){Invoke-SetupGuiFreshVerification -PackageRoot $package -Role Icons}else{Invoke-SetupGuiRole -PackageRoot $package -Role Icons -IconMode $mode}
 $paths=Get-SetupGuiRunPaths -CommonDataRoot $temp -Role Icons -RunId $r.RunId
 $context=Read-SetupGuiContext -CodeRoot $paths.CodeRoot -CommonDataRoot $temp -Role Icons -RunId $r.RunId
 Assert ($r.Success -and $context.IconMode -ceq $mode -and $context.SourcePackageRoot -ceq $package -and $r.SessionId -eq 4) ('actual '+$mode+' mode uses finite protected context and current scope')
 Assert (([NUC8Icons.Desktop]::Moves-$beforeMoves) -eq $(if($mode -eq 'Load'){4}else{0})) ('only Load moves native icons: '+$mode)
 Assert (-not(Test-Path -LiteralPath (Join-Path $paths.CodeRoot 'modules/desktop/desktop_layout.json'))) ('mutable layout is never a pinned code input: '+$mode)
 if($mode -eq 'Save'){$saved=Get-Content -LiteralPath $reference -Raw|ConvertFrom-Json;Assert ($saved.Width -eq 1920 -and $saved.Icons.Count -eq 4) 'Save controller atomically persists bound worker Reference to original fixed template';$null=Read-SetupGuiContext -CodeRoot $paths.CodeRoot -CommonDataRoot $temp -Role Icons -RunId $r.RunId;Assert $true 'Save leaves all staged source hashes valid'}
}
$bad=[pscustomobject]@{Width=1920;Height=1080;Icons=@()};$before=[IO.File]::ReadAllText($reference);$failure=''
try{Write-SetupIconReference -PackageRoot $package -Reference $bad}catch{$failure=$_.Exception.Message}
Assert ($failure -and [IO.File]::ReadAllText($reference) -ceq $before) 'invalid returned Reference cannot replace existing template'