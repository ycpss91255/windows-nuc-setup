#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
function Assert([bool]$Condition,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw $Name}}
function Reject([scriptblock]$Action,[string]$Name){$caught=$false;try{& $Action|Out-Null}catch{$caught=$true};Assert $caught $Name}
$library=Join-Path $root 'modules/cleanup/residue_library.ps1'
Assert (Test-Path -LiteralPath $library) '清理邏輯可由具名原始library安全載入'
. $library
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('residue_'+[guid]::NewGuid().ToString('N'))
$system=Join-Path $fixture 'system';$profile=Join-Path $fixture 'profile';$result=Join-Path $fixture 'result'
[void][IO.Directory]::CreateDirectory($system);[void][IO.Directory]::CreateDirectory($profile)
$argsMap=@{SystemRoot=$system;UserProfile=$profile;ResultRoot=$result;UserSid='S-1-5-21-123'}
function Folder([string]$Path){[void][IO.Directory]::CreateDirectory($Path)}
function File([string]$Path,[string]$Text='fixture'){[IO.File]::WriteAllText($Path,$Text)}
Folder (Join-Path $system 'Windows.old');File (Join-Path $system 'Windows.old/desktop.ini')
foreach($name in @('Contacts','Saved Games','Favorites','Links','Searches')){Folder (Join-Path $profile $name)}
File (Join-Path $profile 'Contacts/important.txt') 'keep'
File (Join-Path $profile 'Favorites/Bing.url')
Folder (Join-Path $profile 'Favorites/Links');File (Join-Path $profile 'Favorites/Links/desktop.ini')
File (Join-Path $profile 'Links/Desktop.lnk');File (Join-Path $profile 'Links/Downloads.lnk')
File (Join-Path $profile 'Searches/Everywhere.search-ms');File (Join-Path $profile 'Searches/Indexed Locations.search-ms')
File (Join-Path $profile 'Searches/winrt--{S-1-5-21-123}-.searchconnector-ms')
Reject {Invoke-SetupResidueCleanup @argsMap -VerifyOnly} 'VerifyOnly 回報空殘留未清除'
Assert (Test-Path (Join-Path $profile 'Favorites/Bing.url')) 'VerifyOnly 保留預設捷徑'
Assert (Test-Path (Join-Path $system 'Windows.old')) 'VerifyOnly 保留空資料夾'
Invoke-SetupResidueCleanup @argsMap|Out-Null
Assert ([IO.File]::ReadAllText((Join-Path $profile 'Contacts/important.txt')) -eq 'keep') '含資料的個人資料夾保留'
foreach($name in @('Saved Games','Favorites','Links','Searches')){Assert (-not(Test-Path (Join-Path $profile $name))) ('移除僅含預設資料的資料夾 '+$name)}
Assert (-not(Test-Path (Join-Path $system 'Windows.old'))) '移除僅含metadata的Windows.old'
Assert ((Test-Path $profile) -and (Test-Path $system)) '不刪除傳入根目錄'
$report=Get-Content (Join-Path $result 'Residue-Result.json') -Raw|ConvertFrom-Json
Assert ($report.Success -and $report.Items.Count -eq 6) '結果完整記錄六個固定目標'
Invoke-SetupResidueCleanup @argsMap -VerifyOnly|Out-Null
$report=Get-Content (Join-Path $result 'Residue-Result.json') -Raw|ConvertFrom-Json
Assert (@($report.Items|Where-Object Status -eq 'Absent').Count -eq 5) '重跑正確記錄不存在的目標'
Folder (Join-Path $system 'Windows.old');File (Join-Path $system 'Windows.old/data.txt') 'old data'
Folder (Join-Path $profile 'Favorites');Folder (Join-Path $profile 'Favorites/Links');File (Join-Path $profile 'Favorites/Links/custom.txt')
Invoke-SetupResidueCleanup @argsMap|Out-Null
Assert (Test-Path (Join-Path $system 'Windows.old/data.txt')) 'Windows.old 實際資料不擴大刪除'
Assert (Test-Path (Join-Path $profile 'Favorites/Links/custom.txt')) '巢狀自訂收藏保留'
Reject {Invoke-SetupResidueCleanup -SystemRoot $system -UserProfile ([IO.Path]::GetPathRoot($profile)) -ResultRoot $result -UserSid 'x'} '拒絕磁碟根作使用者資料夾'
Reject {Invoke-SetupResidueCleanup -SystemRoot (Join-Path $fixture 'missing') -UserProfile $profile -ResultRoot $result -UserSid 'x'} '拒絕不存在的系統根'
function Get-Item {param([string]$LiteralPath,[switch]$Force) [pscustomobject]@{Attributes=[IO.FileAttributes]::ReparsePoint;Parent=$null}}
try{Reject {Invoke-SetupResidueCleanup @argsMap} '根路徑重新解析點在任何清理前拒絕'}finally{Remove-Item Function:\Get-Item}
Write-Host 'ALL PASS: residue named source tests'
