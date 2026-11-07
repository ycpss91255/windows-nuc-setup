#Requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$PackageRoot,[switch]$SourceOnly)
$ErrorActionPreference='Stop'
$count=0
function Assert([bool]$Condition,[string]$Message){if(-not $Condition){throw ('FAIL: '+$Message)};$script:count++;Write-Host ('PASS: '+$Message)}
. (Join-Path $PackageRoot 'Core\Paths.ps1')
$root=[IO.Path]::GetFullPath($PackageRoot).TrimEnd('\')+'\'
foreach($property in $script:NucPathMap.PSObject.Properties){
 $resolved=Resolve-NucPath $property.Name
 Assert ([IO.Path]::GetFullPath($resolved).StartsWith($root,[StringComparison]::OrdinalIgnoreCase)) ('mapped path stays inside package: '+$property.Name)
 if($property.Name -notmatch '(Result|Verification)\.json$' -and -not ($SourceOnly -and $property.Name -eq 'Autologon64.exe')){Assert (Test-Path -LiteralPath $resolved) ('mapped source exists: '+$property.Name)}
}
$config=[IO.File]::ReadAllText((Resolve-NucPath 'Configure-NUC.ps1'))
$modules=@('Apply-AutologonSettings.ps1')+@([regex]::Matches($config,"File='([^']+\.ps1)'" )|ForEach-Object {$_.Groups[1].Value})
Assert ($modules.Count -eq 19 -and @($modules|Select-Object -Unique).Count -eq 19) 'all 19 stages remain unique'
foreach($name in $modules){Assert (Test-Path -LiteralPath (Resolve-NucPath $name) -PathType Leaf) ('stage resolves: '+$name)}
foreach($name in @('Setup-Result.json','Setup-Progress.json','Verification-Result.json','Acceptance-Result.json','Audit-Result.json')){
 Assert ((Resolve-NucPath $name) -eq (Join-Path (Join-Path $PackageRoot 'Reports') $name)) ('aggregate output resolves to Reports: '+$name)
}
foreach($name in @('Display-Verification.json','Theme-Verification.json','IconLayout-Result.json')){
 Assert ((Resolve-NucPath $name) -match '\\Modules\\') ('module output stays beside producer: '+$name)
}
Assert (Test-Path -LiteralPath (Join-Path (Get-NucDriverRoot) 'manifest.json')) 'driver manifest resolves after relocation'
$driverManifest=[IO.File]::ReadAllText((Join-Path (Get-NucDriverRoot) 'manifest.json'))|ConvertFrom-Json
Assert (@($driverManifest).Count -eq 4) 'driver manifest contains four expected payload entries'
Assert (@($driverManifest.File|Select-Object -Unique).Count -eq 4) 'driver manifest filenames are unique'
foreach($entry in $driverManifest){
 Assert ($entry.File -match '^[^\\/:]+\.zip$' -and $entry.File -notmatch '^\.\.') 'driver manifest filename is a local ZIP name'
 Assert ($entry.SHA256 -match '^[A-Fa-f0-9]{64}$') 'driver manifest SHA256 is valid metadata'
}
$owned=@(Get-ChildItem (Join-Path $PackageRoot 'Core') -Filter '*.ps1')+@(Get-ChildItem (Join-Path $PackageRoot 'Modules') -Recurse -Filter '*.ps1'|Where-Object FullName -notmatch '[\\/]Win11Debloat[\\/]')
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
$cmds=@(Get-ChildItem $PackageRoot -Filter '*.cmd')+@(Get-ChildItem (Join-Path $PackageRoot 'Modules') -Recurse -Filter '*.cmd'|Where-Object FullName -notmatch '[\\/]Win11Debloat[\\/]')+@(Get-ChildItem (Join-Path $PackageRoot 'Core') -Filter '*.cmd')
foreach($file in $cmds){
 $text=[IO.File]::ReadAllText($file.FullName)
 foreach($match in [regex]::Matches($text,'"%~dp0([^"\r\n]+\.ps1)"')){
  Assert (Test-Path -LiteralPath (Join-Path $file.DirectoryName $match.Groups[1].Value)) ('CMD target exists: '+$file.Name)
 }
}
$workers=@('Apply-DisplaySettings.ps1','Apply-ThemeSettings.ps1','Apply-DesktopSettings.ps1','Apply-StartMenuSettings.ps1','Apply-TaskbarSettings.ps1','Apply-ExplorerSettings.ps1','Desktop-IconLayout.ps1','Install-WindowsUpdates.ps1','Terminal-HotkeyListener.ps1')
foreach($name in $workers){
 $text=[IO.File]::ReadAllText((Resolve-NucPath $name))
 Assert ($text -notmatch 'Resolve-NucPath|Get-NucDriverRoot|Core\\Paths|NucPackageRoot') ('copied worker has no package path helper dependency: '+$name)
}
# Exercise only the dispatcher against harmless stub entries in a temporary fixture.
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('NUC-Routing-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture|Out-Null
Copy-Item -LiteralPath (Join-Path $PackageRoot 'Core\Start-Windows.ps1') -Destination (Join-Path $fixture 'Start-Windows.ps1')
foreach($entry in @('Configure-NUC.ps1','Verify-AfterRestart.ps1','Verify-Only.ps1')){[IO.File]::WriteAllText((Join-Path $fixture $entry),"Write-Output '$entry'")}
Assert ((& (Join-Path $fixture 'Start-Windows.ps1')) -eq 'Configure-NUC.ps1') 'Windows default dispatches setup'
Assert ((& (Join-Path $fixture 'Start-Windows.ps1') -AfterRestart) -eq 'Verify-AfterRestart.ps1') 'Windows AfterRestart dispatches continuation'
Assert ((& (Join-Path $fixture 'Start-Windows.ps1') -VerifyOnly) -eq 'Verify-Only.ps1') 'Windows VerifyOnly dispatches read-only check'
$rejected=$false;try{& (Join-Path $fixture 'Start-Windows.ps1') -AfterRestart -VerifyOnly}catch{$rejected=$true}
Assert $rejected 'mutually exclusive dispatcher options rejected'
Write-Host ('ALL PASS: '+$count+' layout/routing assertions. No Windows settings were executed.')
