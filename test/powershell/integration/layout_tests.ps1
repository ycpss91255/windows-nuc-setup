#Requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$PackageRoot,[switch]$SourceOnly)
$ErrorActionPreference='Stop'
$count=0
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Message)};$script:count++;Write-Host ('PASS: '+$Message)}
. (Join-Path $PackageRoot 'core\paths.ps1')
$root=[IO.Path]::GetFullPath($PackageRoot).TrimEnd('\')+'\'
# Windows resolves case-insensitively; verify the portable Git names explicitly.
$tracked=if(Test-Path -LiteralPath (Join-Path $PackageRoot '.git')){@(& git -C $PackageRoot -c core.quotePath=false ls-files)}else{@(Get-ChildItem $PackageRoot -Recurse -File|ForEach-Object {$_.FullName.Substring($PackageRoot.TrimEnd('\').Length+1).Replace('\','/')})}
foreach($path in $tracked){
 if($path -cmatch '^modules/debloat/win11debloat/'){continue}
 Assert ((Split-Path $path -Leaf) -cmatch '^[a-z0-9_.]+$') ('owned filename is lowercase snake_case: '+$path)
 $parts=$path -split '/'
 foreach($part in @($parts|Select-Object -SkipLast 1)){
  Assert ($part -cmatch '^[a-z0-9_.-]+$') ('owned directory is lowercase: '+$path)
 }
}
foreach($property in $script:NucPathMap.PSObject.Properties){
 $path=$property.Value.Replace('\','/')
 if($property.Name -match '(Result|Verification)\.json$' -or $property.Name -eq 'Autologon64.exe'){continue}
 $exact=@($tracked|Where-Object {$_ -ceq $path -or $_.StartsWith($path+'/',[StringComparison]::Ordinal)})
 Assert ($exact.Count -gt 0) ('mapped path matches exact Git spelling: '+$path)
}
foreach($entry in @('init.cmd','windows.cmd')){
 $text=[IO.File]::ReadAllText((Join-Path $PackageRoot $entry))
 foreach($match in [regex]::Matches($text,'%~dp0([^"\r\n]+\.ps1)')){
  Assert ($tracked -ccontains $match.Groups[1].Value.Replace('\','/')) ('root CMD uses exact Git path: '+$entry)
 }
}
$workflow=[IO.File]::ReadAllText((Join-Path $PackageRoot '.github/workflows/windows_tests.yml'))
foreach($match in [regex]::Matches($workflow,'\.\\((?:core|test|script)\\[A-Za-z0-9_.\\-]+\.ps1)')){
 Assert ($tracked -ccontains $match.Groups[1].Value.Replace('\','/')) ('workflow uses exact Git path: '+$match.Groups[1].Value)
}
foreach($property in $script:NucPathMap.PSObject.Properties){
 $resolved=Resolve-NucPath $property.Name
 Assert ([IO.Path]::GetFullPath($resolved).StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) ('mapped path stays inside package: '+$property.Name)
 if($property.Name -notmatch '(Result|Verification)\.json$' -and -not ($SourceOnly -and $property.Name -eq 'Autologon64.exe')){Assert (Test-Path -LiteralPath $resolved) ('mapped source exists: '+$property.Name)}
}
$config=[IO.File]::ReadAllText((Resolve-NucPath 'configure_nuc.ps1'))
$modules=@('apply_autologon_settings.ps1')+@([regex]::Matches($config,"File='([^']+\.ps1)'" )|ForEach-Object {$_.Groups[1].Value})
Assert ($modules.Count -eq 19 -and @($modules|Select-Object -Unique).Count -eq 19) 'all 19 stages remain unique'
foreach($name in $modules){Assert (Test-Path -LiteralPath (Resolve-NucPath $name) -PathType Leaf) ('stage resolves: '+$name)}
foreach($name in @('Setup-Result.json','Setup-Progress.json','Verification-Result.json','Acceptance-Result.json','Audit-Result.json')){
 Assert ((Resolve-NucPath $name) -eq (Join-Path (Join-Path $PackageRoot 'reports') $name)) ('aggregate output resolves to Reports: '+$name)
}
foreach($name in @('Display-Verification.json','Theme-Verification.json','IconLayout-Result.json')){
 Assert ((Resolve-NucPath $name) -match '\\modules\\') ('module output stays beside producer: '+$name)
}
Assert (Test-Path -LiteralPath (Join-Path $PackageRoot 'modules/drivers/manifests/nuc8.json')) 'driver manifest resolves after relocation'
$driverManifest=[IO.File]::ReadAllText((Join-Path $PackageRoot 'modules/drivers/manifests/nuc8.json'))|ConvertFrom-Json
Assert (@($driverManifest).Count -eq 4) 'driver manifest contains four expected payload entries'
Assert (@($driverManifest.File|Select-Object -Unique).Count -eq 4) 'driver manifest filenames are unique'
foreach($entry in $driverManifest){
 Assert ($entry.File -match '^[^\\/:]+\.zip$' -and $entry.File -notmatch '^\.\.') 'driver manifest filename is a local ZIP name'
 Assert ($entry.SHA256 -match '^[A-Fa-f0-9]{64}$') 'driver manifest SHA256 is valid metadata'
}
$owned=@(Get-ChildItem (Join-Path $PackageRoot 'core') -Filter '*.ps1')+@(Get-ChildItem (Join-Path $PackageRoot 'modules') -Recurse -Filter '*.ps1'|Where-Object FullName -notmatch '[\\/]Win11Debloat[\\/]')
foreach($file in $owned){
 $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
 Assert ($errors.Count -eq 0) ('PS5.1 parses: '+$file.Name)
 foreach($command in $ast.FindAll({param($a)$a -is [Management.Automation.Language.CommandAst] -and $a.GetCommandName() -eq 'Resolve-NucPath'},$true)){
  if($command.CommandElements.Count -eq 2 -and $command.CommandElements[1] -is [Management.Automation.Language.StringConstantExpressionAst]){
   $name=$command.CommandElements[1].Value
   if($name -match '\.(ps1|exe)$' -and -not ($SourceOnly -and $name -eq 'Autologon64.exe')){Assert (Test-Path -LiteralPath (Resolve-NucPath $name)) ('Core cross-module source exists: '+$name)}
  }
 }
}
$cmds=@(Get-ChildItem $PackageRoot -Filter '*.cmd')+@(Get-ChildItem (Join-Path $PackageRoot 'modules') -Recurse -Filter '*.cmd'|Where-Object FullName -notmatch '[\\/]Win11Debloat[\\/]')+@(Get-ChildItem (Join-Path $PackageRoot 'core') -Filter '*.cmd')
foreach($file in $cmds){
 $cmdBytes=[IO.File]::ReadAllBytes($file.FullName)
 Assert (-not($cmdBytes.Length -ge 3 -and $cmdBytes[0] -eq 239 -and $cmdBytes[1] -eq 187 -and $cmdBytes[2] -eq 191)) ('CMD has no UTF-8 BOM: '+$file.Name)
 $text=[IO.File]::ReadAllText($file.FullName)
 foreach($match in [regex]::Matches($text,'"%~dp0([^"\r\n]+\.ps1)"')){
  Assert (Test-Path -LiteralPath (Join-Path $file.DirectoryName $match.Groups[1].Value)) ('CMD target exists: '+$file.Name)
 }
}
$workers=@('apply_display_settings.ps1','apply_theme_settings.ps1','apply_desktop_settings.ps1','apply_start_menu_settings.ps1','apply_taskbar_settings.ps1','apply_explorer_settings.ps1','desktop_icon_layout.ps1','install_windows_updates.ps1','terminal_hotkey_listener.ps1')
foreach($name in $workers){
 $text=[IO.File]::ReadAllText((Resolve-NucPath $name))
 Assert ($text -notmatch 'Resolve-NucPath|Get-NucDriverRoot|core\\Paths|NucPackageRoot') ('copied worker has no package path helper dependency: '+$name)
}
# Exercise only the dispatcher against harmless stub entries in a temporary fixture.
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('NUC-Routing-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture|Out-Null
Copy-Item -LiteralPath (Join-Path $PackageRoot 'core\start_windows.ps1') -Destination (Join-Path $fixture 'start_windows.ps1')
foreach($entry in @('configure_nuc.ps1','verify_after_restart.ps1','verify_only.ps1')){[IO.File]::WriteAllText((Join-Path $fixture $entry),"Write-Output '$entry'")}
Assert ((& (Join-Path $fixture 'start_windows.ps1')) -eq 'configure_nuc.ps1') 'Windows default dispatches setup'
Assert ((& (Join-Path $fixture 'start_windows.ps1') -AfterRestart) -eq 'verify_after_restart.ps1') 'Windows AfterRestart dispatches continuation'
Assert ((& (Join-Path $fixture 'start_windows.ps1') -VerifyOnly) -eq 'verify_only.ps1') 'Windows VerifyOnly dispatches read-only check'
$rejected=$false;try{& (Join-Path $fixture 'start_windows.ps1') -AfterRestart -VerifyOnly}catch{$rejected=$true}
Assert $rejected 'mutually exclusive dispatcher options rejected'
[IO.File]::WriteAllText((Join-Path $fixture 'configure_nuc.ps1'),'param([string]$DriverPackagePath) $DriverPackagePath')
Push-Location $fixture
try{$selected=& (Join-Path $fixture 'start_windows.ps1') -DriverPackagePath '.\driver_pack'}finally{Pop-Location}
Assert ($selected -eq (Join-Path $fixture 'driver_pack')) '主入口相對驅動路徑依 PowerShell 位置解析'
$systemStatus=& (Join-Path $PackageRoot 'test\powershell\system\invoke_acceptance.ps1')
Assert ($systemStatus.Status -eq 'NotRun' -and -not $systemStatus.Executed) 'system 入口未明確選擇時不執行實機驗收'
Write-Host ('ALL PASS: '+$count+' layout/routing assertions. No Windows settings were executed.')
