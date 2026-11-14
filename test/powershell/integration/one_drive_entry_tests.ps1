#Requires -Version 5.1
$ErrorActionPreference='Stop'
$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
$tokens=$null;$parseErrors=$null
$entryAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repo 'modules/debloat/remove_one_drive.ps1'),[ref]$tokens,[ref]$parseErrors)
Assert ($parseErrors.Count -eq 0 -and $entryAst.ScriptRequirements.IsElevationRequired) '實際入口維持管理員要求'
$imports=@($entryAst.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.InvocationOperator -eq [Management.Automation.Language.TokenKind]::Dot},$true))
$libraryImports=@($imports|Where-Object {@($_.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -ceq 'Join-Path' -and $n.CommandElements.Count -eq 3 -and $n.CommandElements[1].Extent.Text -ceq '$PSScriptRoot' -and $n.CommandElements[2].Value -ceq 'one_drive_library.ps1'},$true)).Count -eq 1})
Assert ($libraryImports.Count -eq 1) '實際入口載入同目錄 OneDrive library'
$entryCalls=@($entryAst.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.GetCommandName() -ceq 'Invoke-OneDriveRemovalEntry'},$true))
Assert ($entryCalls.Count -eq 1 -and $entryCalls[0].CommandElements.Count -eq 2 -and $entryCalls[0].CommandElements[1].ParameterName -ceq 'VerifyOnly' -and $entryCalls[0].CommandElements[1].Argument.Extent.Text -ceq '$VerifyOnly') '實際入口呼叫具名函式並轉送 VerifyOnly'
$ownedTemp=[IO.Path]::GetFullPath($env:TEMP).TrimEnd('\','/')
$fixture=[IO.Path]::GetFullPath((Join-Path $ownedTemp ('onedrive_entry_'+[guid]::NewGuid().ToString('N'))))
if(-not $fixture.StartsWith($ownedTemp+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'fixture path outside owned TEMP'}
function Assert-OneDriveFixturePath([string]$Path) {
 $full=[IO.Path]::GetFullPath($Path).TrimEnd('\','/')
 if(-not $full.Equals($fixture,[StringComparison]::OrdinalIgnoreCase) -and -not $full.StartsWith($fixture+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'fixture path outside owned TEMP'}
 $parent=[IO.Path]::GetDirectoryName($full)
 while($parent -and $parent.StartsWith($fixture,[StringComparison]::OrdinalIgnoreCase)){
  if(([IO.Directory]::Exists($parent) -or [IO.File]::Exists($parent)) -and ([IO.File]::GetAttributes($parent) -band [IO.FileAttributes]::ReparsePoint)){throw 'fixture path crosses reparse point'}
  if($parent.Equals($fixture,[StringComparison]::OrdinalIgnoreCase)){break};$parent=[IO.Path]::GetDirectoryName($parent)
 }
}
$null=New-Item -ItemType Directory -Path (Join-Path $fixture 'OneDrive')
[IO.File]::WriteAllText((Join-Path $fixture 'OneDrive/keep.txt'),'personal data')
. (Join-Path $repo 'modules/debloat/one_drive_library.ps1')
$blocked=$false
try{Assert-OneDriveFixturePath -Path ([IO.Path]::GetPathRoot($fixture))}catch{$blocked=$_.Exception.Message -eq 'fixture path outside owned TEMP'}
Assert $blocked '越界路徑在操作前由 fixture guard 拒絕'
$oldProfile=$env:USERPROFILE;$oldData=$env:ProgramData
try{
 $env:USERPROFILE=$fixture;$env:ProgramData=$fixture;$script:removed=$false
 $registryRoots=@('HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall','HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall')
 $fakeExecutables=@((Join-Path $env:LOCALAPPDATA 'Microsoft/OneDrive/OneDrive.exe'),(Join-Path $env:ProgramFiles 'Microsoft OneDrive/OneDrive.exe'))
 if(${env:ProgramFiles(x86)}){$fakeExecutables+=(Join-Path ${env:ProgramFiles(x86)} 'Microsoft OneDrive/OneDrive.exe')}
 function Test-Path {param($LiteralPath,$Path,$PathType,$ErrorAction);$p=if($LiteralPath){$LiteralPath}else{$Path};if($p -in $registryRoots){return $true};if($p -in $fakeExecutables){return (-not $script:removed)};Assert-OneDriveFixturePath $p;if($PathType){Microsoft.PowerShell.Management\Test-Path -LiteralPath $p -PathType $PathType}else{Microsoft.PowerShell.Management\Test-Path -LiteralPath $p}}
 function Get-ChildItem {param($LiteralPath,$Path,[switch]$Force,$ErrorAction);$p=if($LiteralPath){$LiteralPath}else{$Path};if($p -in $registryRoots){if(-not $script:removed){[pscustomobject]@{PSPath='HKCU:\fixture'}}}else{Assert-OneDriveFixturePath $p;if(([IO.File]::GetAttributes($p) -band [IO.FileAttributes]::ReparsePoint)){throw 'fixture directory is reparse point'};Microsoft.PowerShell.Management\Get-ChildItem -LiteralPath $p -Force:$Force}}
 function Get-Item {param($LiteralPath,[switch]$Force,$ErrorAction);Assert-OneDriveFixturePath $LiteralPath;Microsoft.PowerShell.Management\Get-Item -LiteralPath $LiteralPath -Force:$Force}
 function Remove-Item {param($LiteralPath,[switch]$Force,$ErrorAction);Assert-OneDriveFixturePath $LiteralPath;Microsoft.PowerShell.Management\Remove-Item -LiteralPath $LiteralPath -Force:$Force}
 function Get-ItemProperty {param($LiteralPath,$Path,$ErrorAction);if($LiteralPath -cne 'HKCU:\fixture'){throw 'unexpected registry query'};if(-not $script:removed){[pscustomobject]@{DisplayName='Microsoft OneDrive';UninstallString='"C:\Program Files\OneDriveSetup.exe" /uninstall'}}}
 function Get-Process {param($Name,$ErrorAction);if($Name -and $Name -ne 'OneDrive'){throw 'unexpected process query'}}
 function Get-AuthenticodeSignature {param($LiteralPath,$ErrorAction);if($LiteralPath -cne 'C:\Program Files\OneDriveSetup.exe'){throw 'unexpected signature path'};[pscustomobject]@{Status='Valid';SignerCertificate=[pscustomobject]@{Subject='O=Microsoft Corporation'}}}
 function Start-Process {param($FilePath,$ArgumentList,[switch]$PassThru);if($FilePath -cne 'C:\Program Files\OneDriveSetup.exe' -or $ArgumentList -cne '/uninstall'){throw 'unexpected process'};$script:removed=$true;$p=[pscustomobject]@{ExitCode=-2147219813};$p|Add-Member ScriptMethod WaitForExit {param($milliseconds);$true};$p}
 $outside=[IO.Path]::GetPathRoot($fixture)
 foreach($action in @({Test-Path -LiteralPath $outside},{Get-ChildItem -LiteralPath $outside},{Get-Item -LiteralPath $outside},{Remove-Item -LiteralPath $outside})){
  $blocked=$false;try{& $action|Out-Null}catch{$blocked=$_.Exception.Message -eq 'fixture path outside owned TEMP'}
  Assert $blocked '越界 provider 查詢或刪除在觸及真實檔案前拒絕'
 }
 $continued=$false;$failure='';try{Invoke-OneDriveRemovalEntry;$continued=$true}catch{$failure=$_.Exception.Message}
 Assert $continued ('actual removal entry returns to Debloat after verified absence; error='+$failure)
 $result=Get-Content (Join-Path $fixture 'NUC8-Setup/OneDrive-Result.json') -Raw|ConvertFrom-Json
 Assert ($result.Success -and $result.VerifiedAbsent -and $result.ExitCodes[0] -eq -2147219813) 'actual entry persists exit code with verified absent evidence'
 Assert (([IO.File]::ReadAllText((Join-Path $fixture 'OneDrive/keep.txt'))) -eq 'personal data') 'personal cloud data retained'
 foreach($profileAlias in @(($fixture+'\.'),($fixture+'\'))){
  $env:USERPROFILE=$profileAlias;$script:removed=$false;$continued=$false;$failure=''
  try{Invoke-OneDriveRemovalEntry;$continued=$true}catch{$failure=$_.Exception.Message}
  Assert $continued ('same actual profile represented by dot or trailing separator must not fail; error='+$failure)
  Assert (([IO.File]::ReadAllText((Join-Path $fixture 'OneDrive/keep.txt'))) -eq 'personal data') 'alias profile cleanup retains actual personal cloud data'
 }
 foreach($invalidProfile in @([IO.Path]::GetPathRoot($fixture),'\\fixture.invalid\share\')){
  $env:USERPROFILE=$invalidProfile;$script:removed=$false;$failure=''
  try{Invoke-OneDriveRemovalEntry}catch{$failure=$_.Exception.Message}
  Assert ($failure -match 'OneDrive 路徑不符' -and $failure.Contains('raw=') -and $failure.Contains('canonical=')) 'drive and share roots are refused with safe raw and canonical path diagnostics'
 }
 $emptyProfile=Join-Path $fixture 'empty_profile';$emptyCloud=Join-Path $emptyProfile 'OneDrive'
 $null=New-Item -ItemType Directory -Path $emptyCloud
 [IO.File]::WriteAllText((Join-Path $emptyCloud 'desktop.ini'),'empty shell metadata')
 [IO.File]::WriteAllText((Join-Path $emptyProfile 'personalKeep.txt'),'outside cloud preserved')
 $env:USERPROFILE=$emptyProfile+'\.';$script:removed=$false
 Invoke-OneDriveRemovalEntry
 Assert (-not(Microsoft.PowerShell.Management\Test-Path -LiteralPath $emptyCloud)) 'canonical profile only removes empty OneDrive shell folder and metadata'
 Assert ([IO.File]::ReadAllText((Join-Path $emptyProfile 'personalKeep.txt')) -eq 'outside cloud preserved') 'cleanup never escapes the profile child into sibling personal files'
 $linkedProfile=Join-Path $fixture 'linked_profile';$linkedCloud=Join-Path $linkedProfile 'OneDrive';$cloudTarget=Join-Path $fixture 'actual_personal_data'
 $null=New-Item -ItemType Directory -Path $linkedProfile,$cloudTarget
 [IO.File]::WriteAllText((Join-Path $cloudTarget 'personalKeep.txt'),'junction target preserved')
 $null=New-Item -ItemType Junction -Path $linkedCloud -Target $cloudTarget
 $blocked=$false;try{Get-ChildItem -LiteralPath $linkedCloud|Out-Null}catch{$blocked=$_.Exception.Message -eq 'fixture directory is reparse point'}
 Assert $blocked 'fixture provider 不追蹤 junction 內容'
 $blocked=$false;try{Test-Path -LiteralPath (Join-Path $linkedCloud 'personalKeep.txt')|Out-Null}catch{$blocked=$_.Exception.Message -eq 'fixture path crosses reparse point'}
 Assert $blocked 'fixture provider 不沿 junction 查詢子項'
 $env:USERPROFILE=$linkedProfile;$script:removed=$false
 Invoke-OneDriveRemovalEntry
 Assert ((Microsoft.PowerShell.Management\Get-Item -LiteralPath $linkedCloud -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) 'OneDrive junction itself remains untouched'
 Assert ([IO.File]::ReadAllText((Join-Path $cloudTarget 'personalKeep.txt')) -eq 'junction target preserved') 'cleanup does not traverse OneDrive reparse point or delete target personal data'
 $env:USERPROFILE=$fixture;$script:entryMode='verify';$script:verifySeen=$false
 function Invoke-OneDriveRemoval {param([switch]$VerifyOnly)
  $script:verifySeen=[bool]$VerifyOnly
  if($script:entryMode -eq 'throw'){throw 'fixture removal failure'}
  return [ordered]@{Success=$true;VerifiedAbsent=$true;ExitCodes=@();RemainingInstallations=0;RemainingExecutables=0;RunningProcesses=0;CheckedAt='fixture'}
 }
 Invoke-OneDriveRemovalEntry -VerifyOnly
 $result=Get-Content (Join-Path $fixture 'NUC8-Setup/OneDrive-Result.json') -Raw|ConvertFrom-Json
 Assert ($script:verifySeen -and $result.Success -and [IO.File]::Exists((Join-Path $fixture 'OneDrive/keep.txt'))) 'VerifyOnly 轉送唯讀模式並保留個人資料'
 $script:entryMode='throw';$failure=''
 try{Invoke-OneDriveRemovalEntry}catch{$failure=$_.Exception.Message}
 $result=Get-Content (Join-Path $fixture 'NUC8-Setup/OneDrive-Result.json') -Raw|ConvertFrom-Json
 Assert ($failure -eq 'fixture removal failure' -and -not $result.Success -and -not $result.VerifiedAbsent -and $result.Error -eq $failure) '清理程序例外仍寫入失敗 JSON 並傳播'
}finally{$env:USERPROFILE=$oldProfile;$env:ProgramData=$oldData}
