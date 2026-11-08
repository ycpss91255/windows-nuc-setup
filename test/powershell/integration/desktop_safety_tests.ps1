#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Message}}
$fixture=Join-Path $env:TEMP ('desktop_safety_'+[guid]::NewGuid().ToString('N'))
$desktop=Join-Path $fixture '桌面';$common=Join-Path $fixture 'Common Desktop'
$fixtureDesktopRoots=@($desktop,$common)
$source=[IO.File]::ReadAllText((Join-Path $root 'modules/desktop/apply_desktop_settings.ps1'))
$prefix=$source.Substring(0,$source.IndexOf('$root=Join-Path'))
$prefix=($prefix -split "`r?`n"|Where-Object {$_ -notmatch '^#Requires' -and $_ -notmatch '^param\('}) -join "`n"
$prefix=$prefix.Replace("Join-Path `$PSScriptRoot 'desktop_safety.ps1'","Join-Path `$root 'modules/desktop/desktop_safety.ps1'").Replace("@([Environment]::GetFolderPath('DesktopDirectory'),[Environment]::GetFolderPath('CommonDesktopDirectory'))",'$fixtureDesktopRoots')
$prefix=$prefix.Replace('$PSScriptRoot','$moduleDirectory')
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
 $Worker=$case.Worker;$SourcePackageRoot=if($case.Worker){$packageRoot}else{''};$PSScriptRoot=$moduleDirectory
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
# Execute worker staging only; no task is registered and no desktop is deleted.
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
$workerBranch=$ast.Find({param($a)$a -is [Management.Automation.Language.IfStatementAst] -and $a.Clauses[0].Item1.Extent.Text -like '-not $Worker*SessionId*'},$true)
$staging=@();foreach($statement in $workerBranch.Clauses[0].Item2.Statements){$staging+=$statement.Extent.Text;if($statement.Extent.Text -match '^\$action='){break}}
function New-ScheduledTaskAction {param($Execute,$Argument);[pscustomobject]@{Arguments=$Argument}}
$originalRoot=$root;$root=Join-Path $fixture 'ProgramData/NUC8-Setup';New-Item -ItemType Directory $root -Force|Out-Null
$PSScriptRoot=Join-Path $originalRoot 'modules/desktop';$PSCommandPath=Join-Path $PSScriptRoot 'apply_desktop_settings.ps1';$SourcePackageRoot=Join-Path $fixture "safe package ' 中文"
$stagingText=($staging -join "`n").Replace('$PSCommandPath','$fixtureScriptPath').Replace('$PSScriptRoot','$fixtureModuleDirectory');$fixtureScriptPath=$PSCommandPath;$fixtureModuleDirectory=$PSScriptRoot
. ([scriptblock]::Create($stagingText))
$workerCommand=$action.Arguments
if($workerCommand.Contains('-EncodedCommand ')){$workerCommand=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String(($workerCommand -split '-EncodedCommand ')[1]))}
Assert ($workerCommand.Contains('-SourcePackageRoot') -and $workerCommand.Contains($SourcePackageRoot.Replace("'","''"))) 'worker invocation retains original package identity including quoted path'
Assert (Test-Path -LiteralPath (Join-Path $root 'desktop_safety.ps1')) 'staged worker includes its safety dependency'