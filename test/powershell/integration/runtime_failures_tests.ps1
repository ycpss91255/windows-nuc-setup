#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$count=0
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Message)};$script:count++;Write-Host ('PASS: '+$Message)}
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('windows_runtime_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $fixture|Out-Null
. (Join-Path $root 'core/verification.ps1')
# Exercise the real orchestration body with filesystem-only module doubles.
# Privilege/preflight are excluded; no production system-setting module is loaded.
$config=[IO.File]::ReadAllText((Join-Path $root 'core/configure_nuc.ps1'))
$body=$config.Substring($config.IndexOf('$log=Resolve-NucPath'))
$prefix=@'
$ErrorActionPreference='Stop'
$caseRoot=$PSScriptRoot
$UserName=$env:USERNAME;$AutoLogonPassword='fixture';$hardware=[pscustomobject]@{Name='Fixture'};$skippedModules=@()
function Resolve-NucPath([string]$Name){
 $path=Join-Path $caseRoot $Name
 if($Name.EndsWith('.ps1') -and -not(Microsoft.PowerShell.Management\Test-Path -LiteralPath $path)){
  $code="Add-Content -LiteralPath '"+(Join-Path $caseRoot 'executed.txt').Replace("'","''")+"' -Value '"+$Name+"'"
  if($env:CASE_MODE -eq 'module-fail' -and $Name -eq 'apply_power_settings.ps1'){$code+="`nthrow 'fixture module failure'"}
  [IO.File]::WriteAllText($path,$code,[Text.UTF8Encoding]::new($true))
 }
 return $path
}
function Start-Transcript {param($Path) }
function Stop-Transcript {Set-Content (Join-Path $caseRoot 'finally.txt') 'done'}
function Get-ItemProperty { [pscustomobject]@{DefaultUserName=$env:USERNAME;AutoAdminLogon='1'} }
function Get-SetupModuleDecision { [pscustomobject]@{Applicable=$true} }
function Get-PnpDevice {if($env:CASE_MODE -eq 'device-fail'){[pscustomobject]@{Status='ERROR'}}}
function Test-Path {param($Path);if([string]$Path -like 'HKLM:*'){return $false};Microsoft.PowerShell.Management\Test-Path -LiteralPath $Path}
'@
foreach($mode in @('success','module-fail','device-fail')){
 $dir=Join-Path $fixture $mode;New-Item -ItemType Directory $dir|Out-Null
 $runner=Join-Path $dir 'run.ps1';[IO.File]::WriteAllText($runner,$prefix+"`n"+$body,[Text.UTF8Encoding]::new($true))
 $oldMode=$env:CASE_MODE;$env:CASE_MODE=$mode;$oldPreference=$ErrorActionPreference;$ErrorActionPreference='Continue'
 try{& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner *> (Join-Path $dir 'output.txt');$code=$LASTEXITCODE}finally{$ErrorActionPreference=$oldPreference;$env:CASE_MODE=$oldMode}
 $report=Get-Content (Join-Path $dir 'Setup-Result.json') -Raw|ConvertFrom-Json
 $progress=Get-Content (Join-Path $dir 'Setup-Progress.json') -Raw|ConvertFrom-Json
 Assert (($code -eq 0) -eq ($mode -eq 'success')) ('Configure child exit reflects '+$mode)
 Assert ($report.Success -eq ($mode -eq 'success') -and $progress.HasErrors -eq ($mode -ne 'success')) ('Configure persisted result and progress reflect '+$mode)
 Assert (Test-Path (Join-Path $dir 'finally.txt')) ('Configure finally runs after '+$mode)
 if($mode -eq 'module-fail'){
  Assert ($report.FailedModules -contains 'apply_power_settings.ps1') 'failed module remains available for retry'
  Assert ((Get-Content (Join-Path $dir 'executed.txt')) -contains 'desktop_icon_layout.ps1') 'later stages execute before aggregate failure'
 }
}
# Load the original file using its explicit no-package/PackageOnly early return.
# Any accidental installation path fails before native commands or system queries.
function Start-Process {throw 'fixture forbids installer processes'}
function pnputil.exe {throw 'fixture forbids pnputil'}
function Add-WindowsDriver {throw 'fixture forbids driver installation'}
function Get-CimInstance {throw 'fixture forbids device queries during safe loading'}
function Get-PnpDevice {throw 'fixture forbids driver device queries during safe loading'}
$previousSystemRoot=$env:SystemRoot
try{
 $env:SystemRoot=Join-Path $fixture 'blocked_native_root'
 $loaded=@(. (Join-Path $root 'modules/drivers/install_drivers.ps1') -PackageOnly -DriverPackagePath '')
 Assert ($loaded.Count -eq 1 -and $loaded[0].Status -eq 'Skipped') 'real driver source takes no-package PackageOnly return without installer commands'
}finally{
 $env:SystemRoot=$previousSystemRoot
 foreach($name in @('Start-Process','pnputil.exe','Add-WindowsDriver','Get-CimInstance','Get-PnpDevice')){Remove-Item -LiteralPath ('Function:\'+$name)}
}
Add-Type -AssemblyName System.IO.Compression.FileSystem
$cache=Join-Path $fixture 'cache';$archive=Join-Path $fixture 'same.zip'
$one=Join-Path $fixture 'one';$two=Join-Path $fixture 'two';New-Item -ItemType Directory $one,$two|Out-Null
[IO.File]::WriteAllText((Join-Path $one 'obsolete.inf'),'old');[IO.File]::WriteAllText((Join-Path $two 'current.inf'),'new')
[IO.Compression.ZipFile]::CreateFromDirectory($one,$archive);$hash1=(Get-FileHash $archive).Hash
$dest1=Expand-CachedDriverArchive -Archive $archive -CacheRoot $cache -SHA256 $hash1
$archive2=Join-Path $fixture 'new.zip';[IO.Compression.ZipFile]::CreateFromDirectory($two,$archive2);Copy-Item $archive2 $archive -Force
$dest2=Expand-CachedDriverArchive -Archive $archive -CacheRoot $cache -SHA256 (Get-FileHash $archive).Hash
Assert ($dest1 -ne $dest2) 'same archive name with new hash selects an independent cache'
Assert ((Test-Path (Join-Path $dest1 'obsolete.inf')) -and -not(Test-Path (Join-Path $dest2 'obsolete.inf')) -and (Test-Path (Join-Path $dest2 'current.inf'))) 'old INF is retained only in old cache and cannot enter new selection'
$reportPath=Join-Path $fixture 'verification.json';$verifyScript=Join-Path $fixture 'verify.ps1'
$writer=@'
param([string]$VerificationRunId)
$record=@{Success=$true;VerificationRunId=$VerificationRunId;Computer=$env:COMPUTERNAME;UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value}
if($env:CASE_MODE -eq 'throw'){throw 'fixture verification failed'}
if($env:CASE_MODE -eq 'stale'){return}
if($env:CASE_MODE -eq 'wrong-machine'){$record.Computer='different-machine'}
if($env:CASE_MODE -eq 'wrong-user'){$record.UserSID='different-user'}
$record|ConvertTo-Json|Set-Content -LiteralPath $env:CASE_REPORT -Encoding UTF8
'@
[IO.File]::WriteAllText($verifyScript,$writer,[Text.UTF8Encoding]::new($true))
$oldMode=$env:CASE_MODE;$oldReport=$env:CASE_REPORT;$env:CASE_REPORT=$reportPath
try{
 foreach($mode in @('success','throw','stale','wrong-machine','wrong-user')){
  $env:CASE_MODE=$mode;$accepted=$false
  try{$result=Invoke-FreshVerification -ScriptPath $verifyScript -ReportPath $reportPath;$accepted=[bool]$result.Success}catch{}
  Assert ($accepted -eq ($mode -eq 'success')) ('fresh verification rejects obsolete/failing/wrong-owner result: '+$mode)
 }
}finally{$env:CASE_MODE=$oldMode;$env:CASE_REPORT=$oldReport}
foreach($case in @(@{Selected=0;Updates=@();Expected=$true},@{Selected=1;Updates=@();Expected=$false},@{Selected=2;Updates=@(@{ResultCode=2});Expected=$false},@{Selected=2;Updates=@(@{ResultCode=2},@{ResultCode=3});Expected=$false},@{Selected=1;Updates=@(@{ResultCode=2});Expected=$true},@{Selected=-1;Updates=@();Expected=$false},@{Selected='0';Updates=@();Expected=$false})){
 $r=[pscustomobject]@{Selected=$case.Selected;Updates=$case.Updates}
 Assert ((Test-WindowsUpdateResult $r) -eq $case.Expected) ('update completeness selected='+$case.Selected+' count='+@($case.Updates).Count+' expected='+$case.Expected)
}
# Mock task construction, not scheduling: prove run IDs and ownership reach desktop workers.
function New-ScheduledTaskAction {param($Execute,$Argument);[pscustomobject]@{Arguments=$Argument}}
function New-ScheduledTaskPrincipal {param($UserId,$LogonType,$RunLevel);[pscustomobject]@{UserId=$UserId}}
foreach($relative in @('modules/display/apply_display_settings.ps1','modules/theme/apply_theme_settings.ps1','modules/desktop/desktop_icon_layout.ps1')){
 $source=[IO.File]::ReadAllText((Join-Path $root $relative))
 $VerificationRunId=[guid]::NewGuid().ToString();$VerifyOnly=$true;$Mode='Verify';$workerPath='C:\fixture\worker.ps1'
 if($relative -notmatch 'desktop_icon_layout'){
  $start=$source.IndexOf(" `$workerArgs=");$end=$source.IndexOf(" `$principal=",$start)
  . ([scriptblock]::Create($source.Substring($start,$end-$start)))
 }else{
  $line=($source -split "`n"|Where-Object {$_ -match '^\s*\$action=New-ScheduledTaskAction'})
  . ([scriptblock]::Create($line))
 }
 Assert ($action.Arguments.Contains('-VerificationRunId '+$VerificationRunId)) ('desktop worker receives exact run ID: '+$relative)
 if($relative -notmatch 'desktop_icon_layout'){Assert ($action.Arguments.Contains('-VerifyOnly')) ('desktop worker preserves VerifyOnly: '+$relative)}
 $line=($source -split "`n"|Where-Object {$_ -match '^\s*\$principal=New-ScheduledTaskPrincipal'})
 . ([scriptblock]::Create($line))
 Assert ($principal.UserId -eq [Security.Principal.WindowsIdentity]::GetCurrent().Name) ('desktop worker uses invoking identity: '+$relative)
}
# Execute the actual Verify-Only finalization and AfterRestart acceptance tail.
$verifyTokens=$null;$verifyErrors=$null
$verifyAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'core/verification_library.ps1'),[ref]$verifyTokens,[ref]$verifyErrors)
$verifyFunction=$verifyAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-SetupVerification'},$true)
$verifyStarted=$false
$verifyTail=(@(foreach($statement in $verifyFunction.Body.EndBlock.Statements){if($statement.Extent.Text.StartsWith('$result=[ordered]')){$verifyStarted=$true};if($verifyStarted){$statement.Extent.Text}}) -join "`r`n")
$afterSource=[IO.File]::ReadAllText((Join-Path $root 'core/verify_after_restart.ps1'))
$afterTail=$afterSource.Substring($afterSource.IndexOf('$verificationRunId='))
foreach($mode in @('fresh-failure','stale-success')){
 $dir=Join-Path $fixture $mode;New-Item -ItemType Directory $dir|Out-Null
 $verifyPrefix=@'
param([string]$VerificationRunId)
$ErrorActionPreference='Stop'
$hardware=[pscustomobject]@{Name='Fixture'}
$checks=New-Object Collections.Generic.List[object]
$checks.Add([pscustomobject]@{Name='fixture-check';Status='Failed';Passed=$false})
function Test-SetupChecksPassed {param($Checks);return $false}
function Resolve-NucPath([string]$Name){Join-Path $PSScriptRoot $Name}
'@
 $verifier=Join-Path $dir 'verify_only.ps1'
 [IO.File]::WriteAllText($verifier,$verifyPrefix+"`n"+$verifyTail,[Text.UTF8Encoding]::new($true))
 if($mode -eq 'stale-success'){
  [IO.File]::WriteAllText($verifier,"param([string]`$VerificationRunId)`nthrow 'fixture could not run'",[Text.UTF8Encoding]::new($true))
  @{Passed=$true;Checks=@();VerificationRunId='old-run';Computer=$env:COMPUTERNAME;UserSID=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value}|ConvertTo-Json|Set-Content (Join-Path $dir 'Verification-Result.json') -Encoding UTF8
 }
 $afterPrefix=@'
$ErrorActionPreference='Stop'
$errors=@();$hardware=[pscustomobject]@{Name='Fixture'}
function Resolve-NucPath([string]$Name){Join-Path $PSScriptRoot $Name}
'@
 $runner=Join-Path $dir 'acceptance.ps1';[IO.File]::WriteAllText($runner,$afterPrefix+"`n"+$afterTail,[Text.UTF8Encoding]::new($true))
 $oldPreference=$ErrorActionPreference;$ErrorActionPreference='Continue'
 try{& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $runner *> (Join-Path $dir 'output.txt');$code=$LASTEXITCODE}finally{$ErrorActionPreference=$oldPreference}
 $accepted=Get-Content (Join-Path $dir 'Acceptance-Result.json') -Raw|ConvertFrom-Json
 Assert ($code -ne 0 -and -not $accepted.Success) ('acceptance persists failed result then returns nonzero: '+$mode)
 if($mode -eq 'fresh-failure'){Assert (@($accepted.FailedChecks).Count -eq 1) 'Verify-Only exception does not discard current failed checks'}
 else{Assert (@($accepted.Errors|Where-Object {$_ -match '本輪'}).Count -gt 0) 'stale successful verification cannot bypass acceptance'}
}
Write-Host ('ALL PASS: '+$count+' runtime regression assertions; temporary files only, no host configuration or driver installation.')
