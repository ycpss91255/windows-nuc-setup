#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'modules/init/init_entry_library.ps1')
$fixture=Join-Path $env:TEMP ('audit_guard_'+[guid]::NewGuid().ToString('N'))
$module=Join-Path $fixture 'source/modules/init';$assets=Join-Path $module 'assets'
[void][IO.Directory]::CreateDirectory($module)
Copy-Item -LiteralPath (Join-Path $root 'modules/init/assets') -Destination $assets -Recurse
$oldData=$env:ProgramData;$oldWindows=$env:WINDIR
$env:ProgramData=Join-Path $fixture 'data';$env:WINDIR=Join-Path $fixture 'windows'
$script:calls=New-Object 'Collections.Generic.List[string]'
$script:metadata='valid'
function Get-InitProvisioningContext { [pscustomobject]@{Sid='S-1-5-21-1-2-3-500';IsAdministrator=$true} }
function Get-SetupInitContext { [pscustomobject]@{Sid='S-1-5-21-1-2-3-500';UserSID='fixture';IsAdministrator=$true;ImageState='IMAGE_STATE_UNDEPLOYABLE';DesktopOwned=$true;Is64Bit=$true;Architecture='AMD64';ModeFacts=@{ReadSucceeded=$true;Build=26200;ProductType=1;IsWinPE=$false;OobeApiSucceeded=$true;OobeComplete=$false;SetupInProgress=0;OobeInProgress=0;OobeProcessInSession=$false;SetupProcessInSession=$false;ProfileMatches=$true;LocalBuiltin=$true}} }
function Get-Process {param($Name,$ErrorAction)}
function Get-ItemProperty {param($Path,$ErrorAction) [pscustomobject]@{SkuPolicyRequired=0;UnattendFile=''} }
function Get-InitAnswerCandidates {param($WindowsPath) @()}
function Assert-InitPlainPath {param($Path)}
function Test-Path {param($LiteralPath,$PathType,$ErrorAction) if($LiteralPath -like '*Sysprep.exe'){return $true}; Microsoft.PowerShell.Management\Test-Path @PSBoundParameters}
function Get-ProvisioningPackage {param($PackagePath,$LogsDirectoryPath,$ErrorAction) $script:calls.Add('metadata');if($script:metadata -eq 'throw'){throw 'native unavailable'};[pscustomobject]@{PackageID='1c2605ea-96ae-42fc-8f11-45fc0cb9d133';PackageName=$(if($script:metadata -eq 'bad'){'bad'}else{'windows_setup_hide_oobe'});Version='1.0';Rank=0;OwnerType=5000} }
function Read-Host {param($Prompt,[switch]$AsSecureString) $script:calls.Add('prompt');throw 'prompt sentinel'}
function Get-LocalUser { $script:calls.Add('account');throw 'unexpected account' }
function New-Item { $script:calls.Add('write');throw 'unexpected write' }
function Start-Process { $script:calls.Add('start');throw 'unexpected process' }
function Invoke-Case {param($Name,[bool]$Valid)
 $script:calls.Clear();$errorText=''
 try{Invoke-SetupInit -EntryPath (Join-Path $module 'entry.ps1') -ModuleRoot $module}catch{$errorText=$_.Exception.Message}
 $ok=if($Valid){$errorText -eq 'prompt sentinel' -and ($script:calls -join ',') -eq 'metadata,prompt'}else{$errorText -ne 'prompt sentinel' -and $script:calls -notcontains 'prompt' -and $script:calls -notcontains 'account' -and $script:calls -notcontains 'write' -and $script:calls -notcontains 'start'}
 Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$ok;Calls=($script:calls -join ',')}|ConvertTo-Json -Compress))
 if(-not $ok){throw $Name}
}
try{
 foreach($name in @('hide_oobe.ppkg','hide_oobe.xml','provenance.json')){
  $path=Join-Path $assets $name;$bytes=[IO.File]::ReadAllBytes($path);[IO.File]::Delete($path)
  try{Invoke-Case ('缺少 '+$name) $false}finally{[IO.File]::WriteAllBytes($path,$bytes)}
 }
 $path=Join-Path $assets 'hide_oobe.xml';$bytes=[IO.File]::ReadAllBytes($path);[IO.File]::AppendAllText($path,'tampered')
 try{Invoke-Case '來源遭竄改' $false}finally{[IO.File]::WriteAllBytes($path,$bytes)}
 $script:metadata='bad';Invoke-Case 'metadata 不符' $false
 $script:metadata='throw';Invoke-Case 'native metadata 失敗' $false
 $script:metadata='valid';Invoke-Case '合法資產先驗證再提示' $true
}finally{$env:ProgramData=$oldData;$env:WINDIR=$oldWindows}
Write-Host 'ALL PASS: Audit isolated asset guard'
