#Requires -Version 5.1
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$fixture=Join-Path $env:TEMP ('onedrive_entry_'+[guid]::NewGuid().ToString('N'));$null=New-Item -ItemType Directory -Path (Join-Path $fixture 'OneDrive')
[IO.File]::WriteAllText((Join-Path $fixture 'OneDrive/keep.txt'),'personal data')
$entry=[IO.File]::ReadAllText((Join-Path $repo 'modules/debloat/remove_one_drive.ps1'))
$entry=($entry -split "`r?`n"|Where-Object {$_ -notmatch '^#Requires'}) -join "`n"
$entry=$entry.Replace('$PSScriptRoot',("'"+(Join-Path $repo 'modules/debloat').Replace("'","''")+"'"))
$oldProfile=$env:USERPROFILE;$oldData=$env:ProgramData
try{
 $env:USERPROFILE=$fixture;$env:ProgramData=$fixture;$script:removed=$false
 function Test-Path {param($LiteralPath,$Path,$PathType,$ErrorAction);$p=if($LiteralPath){$LiteralPath}else{$Path};if($p -like 'HK*'){return $true};if($p -like '*OneDrive.exe'){return (-not $script:removed)};Microsoft.PowerShell.Management\Test-Path -LiteralPath $p}
 function Get-ChildItem {param($LiteralPath,$Path,[switch]$Force,$ErrorAction);$p=if($LiteralPath){$LiteralPath}else{$Path};if($p -like 'HK*'){if(-not $script:removed){[pscustomobject]@{PSPath='HKCU:\fixture'}}}else{Microsoft.PowerShell.Management\Get-ChildItem -LiteralPath $p -Force:$Force}}
 function Get-ItemProperty {param($LiteralPath,$Path,$ErrorAction);if(-not $script:removed){[pscustomobject]@{DisplayName='Microsoft OneDrive';UninstallString='"C:\Program Files\OneDriveSetup.exe" /uninstall'}}}
 function Get-Process {param($Name,$ErrorAction)}
 function Get-AuthenticodeSignature {param($LiteralPath,$ErrorAction);[pscustomobject]@{Status='Valid';SignerCertificate=[pscustomobject]@{Subject='O=Microsoft Corporation'}}}
 function Start-Process {param($FilePath,$ArgumentList,[switch]$PassThru);$script:removed=$true;$p=[pscustomobject]@{ExitCode=-2147219813};$p|Add-Member ScriptMethod WaitForExit {param($milliseconds);$true};$p}
 $continued=$false;$failure='';try{& ([scriptblock]::Create($entry));$continued=$true}catch{$failure=$_.Exception.Message}
 Assert $continued ('actual removal entry returns to Debloat after verified absence; error='+$failure)
 $result=Get-Content (Join-Path $fixture 'NUC8-Setup/OneDrive-Result.json') -Raw|ConvertFrom-Json
 Assert ($result.Success -and $result.VerifiedAbsent -and $result.ExitCodes[0] -eq -2147219813) 'actual entry persists exit code with verified absent evidence'
 Assert (([IO.File]::ReadAllText((Join-Path $fixture 'OneDrive/keep.txt'))) -eq 'personal data') 'personal cloud data retained'
 foreach($profileAlias in @(($fixture+'\.'),($fixture+'\'))){
  $env:USERPROFILE=$profileAlias;$script:removed=$false;$continued=$false;$failure=''
  try{& ([scriptblock]::Create($entry));$continued=$true}catch{$failure=$_.Exception.Message}
  Assert $continued ('same actual profile represented by dot or trailing separator must not fail; error='+$failure)
  Assert (([IO.File]::ReadAllText((Join-Path $fixture 'OneDrive/keep.txt'))) -eq 'personal data') 'alias profile cleanup retains actual personal cloud data'
 }
 foreach($invalidProfile in @([IO.Path]::GetPathRoot($fixture),'\\fixture.invalid\share\')){
  $env:USERPROFILE=$invalidProfile;$script:removed=$false;$failure=''
  try{& ([scriptblock]::Create($entry))}catch{$failure=$_.Exception.Message}
  Assert ($failure -match 'OneDrive 路徑不符' -and $failure.Contains('raw=') -and $failure.Contains('canonical=')) 'drive and share roots are refused with safe raw and canonical path diagnostics'
 }
 $emptyProfile=Join-Path $fixture 'empty_profile';$emptyCloud=Join-Path $emptyProfile 'OneDrive'
 $null=New-Item -ItemType Directory -Path $emptyCloud
 [IO.File]::WriteAllText((Join-Path $emptyCloud 'desktop.ini'),'empty shell metadata')
 [IO.File]::WriteAllText((Join-Path $emptyProfile 'personalKeep.txt'),'outside cloud preserved')
 $env:USERPROFILE=$emptyProfile+'\.';$script:removed=$false
 & ([scriptblock]::Create($entry))
 Assert (-not(Microsoft.PowerShell.Management\Test-Path -LiteralPath $emptyCloud)) 'canonical profile only removes empty OneDrive shell folder and metadata'
 Assert ([IO.File]::ReadAllText((Join-Path $emptyProfile 'personalKeep.txt')) -eq 'outside cloud preserved') 'cleanup never escapes the profile child into sibling personal files'
 $linkedProfile=Join-Path $fixture 'linked_profile';$linkedCloud=Join-Path $linkedProfile 'OneDrive';$cloudTarget=Join-Path $fixture 'actual_personal_data'
 $null=New-Item -ItemType Directory -Path $linkedProfile,$cloudTarget
 [IO.File]::WriteAllText((Join-Path $cloudTarget 'personalKeep.txt'),'junction target preserved')
 $null=New-Item -ItemType Junction -Path $linkedCloud -Target $cloudTarget
 $env:USERPROFILE=$linkedProfile;$script:removed=$false
 & ([scriptblock]::Create($entry))
 Assert ((Microsoft.PowerShell.Management\Get-Item -LiteralPath $linkedCloud -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) 'OneDrive junction itself remains untouched'
 Assert ([IO.File]::ReadAllText((Join-Path $cloudTarget 'personalKeep.txt')) -eq 'junction target preserved') 'cleanup does not traverse OneDrive reparse point or delete target personal data'
}finally{$env:USERPROFILE=$oldProfile;$env:ProgramData=$oldData}
