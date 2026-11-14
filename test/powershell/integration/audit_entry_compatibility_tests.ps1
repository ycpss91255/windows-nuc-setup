#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
$old=Join-Path $root 'core/audit_nuc.ps1';$new=Join-Path $root 'core/audit_setup.ps1';$library=Join-Path $root 'core/audit_entry_library.ps1'
Assert (Test-Path -LiteralPath $new -PathType Leaf) 'neutral audit entry exists'
Assert (Test-Path -LiteralPath $old -PathType Leaf) 'legacy audit wrapper remains'
Assert (Test-Path -LiteralPath $library -PathType Leaf) 'audit entry library exists'
$map=Get-Content (Join-Path $root 'core/paths.json') -Raw|ConvertFrom-Json
Assert ($map.'audit_setup.ps1' -ceq 'core/audit_setup.ps1' -and $map.'audit_nuc.ps1' -ceq 'core/audit_nuc.ps1' -and $map.'Audit-NUC.ps1' -ceq 'core/audit_nuc.ps1' -and $map.'audit_entry_library.ps1' -ceq 'core/audit_entry_library.ps1') 'new and old registered paths preserve legacy wrapper'
. (Join-Path $root 'core/paths.ps1')
Assert ((Resolve-NucPath 'audit_setup.ps1') -ceq $new -and (Resolve-NucPath 'audit_nuc.ps1') -ceq $old -and (Resolve-NucPath 'Audit-NUC.ps1') -ceq $old -and (Resolve-NucModuleName 'Audit-NUC.ps1') -ceq 'audit_nuc.ps1') 'real path resolver preserves legacy aliases and continuation name'
$tokens=$null;$errors=$null;$requiredAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'core/test_setup_prerequisites.ps1'),[ref]$tokens,[ref]$errors)
$strings=@($requiredAst.FindAll({param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst]},$true)|ForEach-Object Value)
Assert ($errors.Count -eq 0 -and 'audit_setup.ps1' -cin $strings -and 'audit_nuc.ps1' -cin $strings -and 'audit_entry_library.ps1' -cin $strings) 'package prerequisites require new and legacy runtime files'
foreach($entry in @($new,$old)){
 $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile($entry,[ref]$tokens,[ref]$errors)
 Assert ($errors.Count -eq 0 -and $ast.ScriptRequirements.IsElevationRequired -and $ast.ScriptRequirements.RequiredPSVersion.Major -eq 5) ('real entry preserves PowerShell 5 and admin guard: '+[IO.Path]::GetFileName($entry))
}
$tokens=$null;$errors=$null;$newAst=[Management.Automation.Language.Parser]::ParseFile($new,[ref]$tokens,[ref]$errors)
$calls=@($newAst.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -eq 'Invoke-SetupAuditEntry'},$true))
Assert ($calls.Count -eq 1) 'neutral entry invokes shared audit entry exactly once'
$tokens=$null;$errors=$null;$oldAst=[Management.Automation.Language.Parser]::ParseFile($old,[ref]$tokens,[ref]$errors)
$oldCommands=@($oldAst.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst]},$true));$oldStrings=@($oldAst.FindAll({param($n) $n -is [Management.Automation.Language.StringConstantExpressionAst]},$true)|ForEach-Object Value)
Assert (@($oldCommands|Where-Object InvocationOperator -eq ([Management.Automation.Language.TokenKind]::Ampersand)).Count -eq 1 -and 'audit_setup.ps1' -cin $oldStrings -and @($oldCommands|Where-Object {$_.GetCommandName() -in @('Invoke-SetupAudit','Invoke-SetupAuditEntry')}).Count -eq 0) 'legacy entry delegates once to neutral entry without duplicate audit'
$fixture=Join-Path $env:TEMP ('audit_entry_'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($fixture)
foreach($file in @($old,$new,$library)){Copy-Item -LiteralPath $file -Destination $fixture}
$fakePaths="function Resolve-NucPath {param([string]`$Name) if(`$Name -cne 'Audit-Result.json'){throw 'unexpected fixture report'};Join-Path `$env:AUDIT_FIXTURE_ROOT `$Name}"
$fakeAudit="function Invoke-SetupAudit {param([string]`$ReportPath) [IO.File]::AppendAllText((Join-Path `$env:AUDIT_FIXTURE_ROOT 'calls.txt'),`$ReportPath+[Environment]::NewLine);if(`$env:AUDIT_FIXTURE_FAIL -eq '1'){throw 'fixture audit failure'}; 'fixture audit result'}"
[IO.File]::WriteAllText((Join-Path $fixture 'paths.ps1'),$fakePaths,[Text.UTF8Encoding]::new($true))
[IO.File]::WriteAllText((Join-Path $fixture 'audit_library.ps1'),$fakeAudit,[Text.UTF8Encoding]::new($true))
$priorRoot=$env:AUDIT_FIXTURE_ROOT;$priorFail=$env:AUDIT_FIXTURE_FAIL
try{
 $env:AUDIT_FIXTURE_ROOT=$fixture;$env:AUDIT_FIXTURE_FAIL='0';. (Join-Path $fixture 'audit_entry_library.ps1')
 $result=@(Invoke-SetupAuditEntry);$log=Join-Path $fixture 'calls.txt'
 Assert ($result.Count -eq 1 -and $result[0] -ceq 'fixture audit result' -and @([IO.File]::ReadAllLines($log)).Count -eq 1 -and ([IO.File]::ReadAllLines($log))[0] -ceq (Join-Path $fixture 'Audit-Result.json')) 'real audit function invokes fixture once and forwards report and output'
 [IO.File]::Delete($log);$env:AUDIT_FIXTURE_FAIL='1';$message=''
 try{Invoke-SetupAuditEntry|Out-Null}catch{$message=$_.Exception.Message}
 Assert ($message -ceq 'fixture audit failure' -and @([IO.File]::ReadAllLines($log)).Count -eq 1) 'real audit function propagates failure without retry'
 $admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
 $ps=Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'
 foreach($entry in @('audit_setup.ps1','audit_nuc.ps1')){foreach($mode in @('0','1')){
  $env:AUDIT_FIXTURE_FAIL=$mode;if(Test-Path $log){[IO.File]::Delete($log)}
  $out=Join-Path $fixture 'out.txt';$err=Join-Path $fixture 'err.txt'
  $process=Start-Process -FilePath $ps -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+(Join-Path $fixture $entry)+'"')) -WindowStyle Hidden -Wait -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
  if($admin){
   Assert (($process.ExitCode -eq 0) -eq ($mode -eq '0')) ('admin real entry forwards success/failure: '+$entry+' '+$mode)
   Assert ((Test-Path $log) -and @([IO.File]::ReadAllLines($log)).Count -eq 1 -and ([IO.File]::ReadAllLines($log))[0] -ceq (Join-Path $fixture 'Audit-Result.json')) ('admin real entry calls audit once with same path: '+$entry+' '+$mode)
  }else{Assert ($process.ExitCode -ne 0 -and ([IO.File]::ReadAllText($err) -match 'ScriptRequiresElevation') -and -not (Test-Path $log)) ('nonadmin real entry refuses before audit: '+$entry+' '+$mode)}
 }}
}finally{$env:AUDIT_FIXTURE_ROOT=$priorRoot;$env:AUDIT_FIXTURE_FAIL=$priorFail}
