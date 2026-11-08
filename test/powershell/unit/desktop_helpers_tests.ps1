#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$library=Join-Path $root 'modules/desktop/desktop_settings_library.ps1'
Assert (Test-Path -LiteralPath $library) 'Desktop cleanup exposes a named original-source leaf without running the public administrator entry'
. $library
Add-Type -TypeDefinition 'using System;public static class NUC8DesktopRefresh{public static int Calls;public static void SHChangeNotify(int e,uint f,IntPtr a,IntPtr b){Calls++;}}'
$temp=Join-Path ([IO.Path]::GetTempPath()) ('desktop_leaf_'+[guid]::NewGuid().ToString('N'))
$source=Join-Path $temp 'package';$userDesktop=Join-Path $temp 'user_desktop';$commonDesktop=Join-Path $temp 'common_desktop';$outside=Join-Path $temp 'outside'
foreach($path in @($source,$userDesktop,$commonDesktop,$outside)){[void][IO.Directory]::CreateDirectory($path)}
[IO.File]::WriteAllText((Join-Path $source 'keep.txt'),'source')
[IO.File]::WriteAllText((Join-Path $outside 'keep.txt'),'outside')
[IO.File]::WriteAllText((Join-Path $userDesktop 'plain.txt'),'delete')
$system=Join-Path $commonDesktop 'desktop.ini';[IO.File]::WriteAllText($system,'keep system');[IO.File]::SetAttributes($system,([IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System))
$nested=Join-Path $userDesktop 'nested';[void][IO.Directory]::CreateDirectory($nested);[IO.File]::WriteAllText((Join-Path $nested 'child.txt'),'delete')
$null=New-Item -ItemType Junction -Path (Join-Path $nested 'link') -Target $outside
$script:writes=@()
function Test-Path {param($Path,$LiteralPath,$PathType) if($Path -like 'HK*'){return $true};Microsoft.PowerShell.Management\Test-Path @PSBoundParameters}
function New-ItemProperty {param($Path,$Name,$Value,$PropertyType,[switch]$Force) if($Path -notlike 'HK*' -or $PropertyType -ne 'DWord' -or -not $Force){throw 'unexpected desktop registry mutation'};$script:writes+=@([pscustomobject]@{Path=$Path;Name=$Name;Value=$Value})}
$r=Invoke-SetupDesktopSettings -ModuleRoot (Join-Path $root 'modules/desktop') -SourcePackageRoot $source -DesktopRoots @($userDesktop,$commonDesktop)
Assert ($r.Success -and @($r.RemainingFiles).Count -eq 0 -and -not(Test-Path -LiteralPath (Join-Path $userDesktop 'plain.txt')) -and -not(Test-Path -LiteralPath $nested)) 'Desktop removes plain fixture files and nested folders'
Assert ([IO.File]::ReadAllText((Join-Path $outside 'keep.txt')) -eq 'outside' -and [IO.File]::ReadAllText((Join-Path $source 'keep.txt')) -eq 'source') 'recursive cleanup removes junction itself without following outside target or deleting source package'
Assert ([IO.File]::ReadAllText($system) -eq 'keep system') 'Desktop preserves hidden system desktop.ini'
Assert ($script:writes.Count -eq 19 -and [NUC8DesktopRefresh]::Calls -eq 1 -and @($script:writes|Where-Object {$_.Name -eq 'HideIcons' -and $_.Value -eq 0}).Count -eq 1) 'Desktop retains approved system icon and Edge shortcut policies and native refresh'
$before=$script:writes.Count;$failure=''
try{Invoke-SetupDesktopSettings -ModuleRoot (Join-Path $root 'modules/desktop') -SourcePackageRoot $userDesktop -DesktopRoots @($userDesktop,$commonDesktop)|Out-Null}catch{$failure=$_.Exception.Message}
Assert ($failure.Contains('工具包不可位於桌面') -and $script:writes.Count -eq $before) 'actual original source on desktop is rejected before any preference write'
$failure='';try{Remove-SetupDesktopEntry -Item (Get-Item -LiteralPath (Join-Path $outside 'keep.txt')) -AllowedRoot $userDesktop}catch{$failure=$_.Exception.Message}
Assert ($failure.Contains('桌面以外') -and [IO.File]::ReadAllText((Join-Path $outside 'keep.txt')) -eq 'outside') 'recursive entry helper refuses an explicit outside-root path'
