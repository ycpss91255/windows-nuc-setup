#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
$fixture=Join-Path $env:TEMP ('desktop_safety_'+[guid]::NewGuid().ToString('N'))
$desktop=Join-Path $fixture '桌面';$common=Join-Path $fixture 'Common Desktop'
$fixtureDesktopRoots=@($desktop,$common)
$source=[IO.File]::ReadAllText((Join-Path $root 'modules/desktop/desktop_settings_library.ps1'))
$tokens=$null;$errors=$null;$leafAst=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
$call=$leafAst.Find({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Assert-DesktopSourceLocation'},$true)
Assert ($null -ne $call) 'actual named leaf invokes original source safety before cleanup'
. (Join-Path $root 'modules/desktop/desktop_safety.ps1')
$prefix=$call.Extent.Text.Replace('$DesktopRoots','$fixtureDesktopRoots')
foreach($case in @(
 @{Name='nested package';Package=(Join-Path $desktop 'windows_setup');Worker=$false;Reject=$true},
 @{Name='package equals desktop';Package=$desktop;Worker=$false;Reject=$true},
 @{Name='common desktop';Package=(Join-Path $common 'windows_setup');Worker=$false;Reject=$true},
 @{Name='worker original desktop source';Package=(Join-Path $desktop 'windows_setup');Worker=$true;Reject=$true},
 @{Name='worker missing source identity';Package='';Worker=$true;Reject=$true},
 @{Name='safe similar prefix';Package=($desktop+'2\windows_setup');Worker=$false;Reject=$false}
)){
 $packageRoot=$case.Package
 if($packageRoot){New-Item -ItemType Directory (Join-Path $packageRoot 'modules/desktop') -Force|Out-Null;[IO.File]::WriteAllText((Join-Path $packageRoot 'keep.txt'),'keep')}
 $moduleDirectory=if($case.Worker){Join-Path $fixture 'ProgramData/NUC8-Setup'}else{Join-Path $packageRoot 'modules/desktop'}
 $Worker=$case.Worker;$SourcePackageRoot=$packageRoot;$PSScriptRoot=$moduleDirectory
 $refused=$false
 try{& ([scriptblock]::Create($prefix))}catch{$refused=$true;if(-not $case.Reject){Write-Host $_.Exception.Message}}
 Assert ($refused -eq $case.Reject) ('actual desktop module pre-mutation guard: '+$case.Name)
 if($packageRoot){Assert (([IO.File]::ReadAllText((Join-Path $packageRoot 'keep.txt'))) -eq 'keep') ('package contents retained: '+$case.Name)}
}
# Exercise the actual main preflight guard with only folder-location inputs substituted.
$preflight=[IO.File]::ReadAllText((Join-Path $root 'core/test_setup_prerequisites.ps1'))
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($preflight,[ref]$tokens,[ref]$errors)
$guard=$ast.Find({param($a)$a -is [Management.Automation.Language.ForEachStatementAst] -and $a.Variable.VariablePath.UserPath -eq 'desktop'},$true)
if($guard){$guardText=$guard.Extent.Text.Replace("@([Environment]::GetFolderPath('DesktopDirectory'),[Environment]::GetFolderPath('CommonDesktopDirectory'))",'$fixtureDesktopRoots')}
else{$guardText=($preflight -split "`r?`n"|Where-Object {$_ -match '^ Assert-DesktopSourceLocation'}) -join "`n";$guardText=$guardText.Replace("@([Environment]::GetFolderPath('DesktopDirectory'),[Environment]::GetFolderPath('CommonDesktopDirectory'))",'$fixtureDesktopRoots')}
$helper=Join-Path $root 'modules/desktop/desktop_safety.ps1';if(Test-Path $helper){. $helper}
foreach($location in @($desktop,(Join-Path $desktop '中文 子目錄'),$common,$desktop.ToUpperInvariant())){
 $script:NucPackageRoot=$location;$refused=$false
 try{. ([scriptblock]::Create($guardText))}catch{$refused=$true}
 Assert $refused ('actual main preflight rejects desktop equality and descendants: '+$location)
}
# Fixed private worker must use the protected original root, not its copied code directory.
$gui=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'core/gui_stage_library.ps1'),[ref]$tokens,[ref]$errors)
$call=$gui.Find({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Invoke-SetupDesktopSettings'},$true)
Assert ($call.Extent.Text.Contains('-SourcePackageRoot $context.SourcePackageRoot') -and -not $call.Extent.Text.Contains('-SourcePackageRoot $CodeRoot')) 'fixed worker receives bound original source identity'
. (Join-Path $root 'core/gui_stage_library.ps1')
Assert (@(Get-SetupGuiStageFiles Desktop) -contains 'modules/desktop/desktop_safety.ps1') 'fixed private worker includes its original safety dependency'