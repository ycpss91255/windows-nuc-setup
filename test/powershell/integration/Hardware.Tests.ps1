#Requires -Version 5.1
$ErrorActionPreference='Stop'
$packageRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
. (Join-Path $packageRoot 'core\Hardware.ps1')
$count=0
function Assert([bool]$Condition,[string]$Message){Write-Host ('@@ASSERT@@'+(@{Name=$Message;Passed=$Condition}|ConvertTo-Json -Compress));if(-not $Condition){throw ('FAIL: '+$Message)};$script:count++;Write-Host ('PASS: '+$Message)}
$generic=Get-SetupHardwareProfile -BoardProduct 'Other Board' -UICulture 'en-US'
$hv=Get-SetupHardwareProfile -BoardProduct 'NUC8i7HVB' -UICulture 'zh-TW' -DriverPackagePath 'selected_package'
$hn=Get-SetupHardwareProfile -BoardProduct 'NUC8i7HNB' -UICulture 'zh-TW' -DriverPackagePath 'selected_package'
$fixture=Join-Path $env:TEMP ('windows_setup_hardware_'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture|Out-Null
Assert ((Test-SetupDriverPayload $generic $fixture).Status -eq 'Skipped') '通用主機在完全無 payload 的目錄通過適用性判斷'
$caught=$false;try{Test-SetupDriverPayload $hv (Join-Path $fixture 'missing')|Out-Null}catch{$caught=$true}
Assert $caught 'NUC 選擇缺少的 payload 仍失敗'
$payload=Join-Path $fixture 'modules\drivers\Payload'
New-Item -ItemType Directory -Path $payload -Force|Out-Null
@{SchemaVersion=1;HardwareProfile='NUC8';Architecture='x64';SupportedBoards=@('NUC8i7HVB','NUC8i7HNB')}|ConvertTo-Json|Set-Content (Join-Path $payload 'package.json') -Encoding UTF8
$manifest=@(1..4|ForEach-Object {$file=('driver'+$_+'.zip');[IO.File]::WriteAllText((Join-Path $payload $file),'fixture');[pscustomobject]@{File=$file;SHA256=(Get-FileHash (Join-Path $payload $file)).Hash}})
$manifest|ConvertTo-Json|Set-Content (Join-Path $payload 'manifest.json') -Encoding UTF8
Assert ((Test-SetupDriverPayload $hn $payload).Count -eq 4) 'NUC 四個獨立檔案雜湊通過'
[IO.File]::WriteAllText((Join-Path $payload 'driver1.zip'),'changed')
$caught=$false;try{Test-SetupDriverPayload $hv $payload|Out-Null}catch{$caught=$true}
Assert $caught 'NUC 雜湊錯誤仍失敗'
@($manifest[1],$manifest[1],$manifest[1],$manifest[1])|ConvertTo-Json|Set-Content (Join-Path $payload 'manifest.json') -Encoding UTF8
$caught=$false;try{Test-SetupDriverPayload $hv $payload|Out-Null}catch{$caught=$true}
Assert $caught '重複四次同一驅動不算完整清單'
# Execute the actual early guards with mocked hardware; remove only the elevation directive.
# Any unexpected mutation is trapped before it can touch the host.
foreach($relative in @('modules\drivers\Install-Drivers.ps1','modules\amd\Apply-AMDPrivacySettings.ps1')){
 $target=Join-Path $packageRoot $relative
 $runner=Join-Path $fixture ([IO.Path]::GetFileName($relative))
 $code=[IO.File]::ReadAllText($target) -replace '(?m)^#Requires -RunAsAdministrator\r?\n',''
 $code=$code.Replace('$PSScriptRoot',("'"+(Split-Path $target -Parent).Replace("'","''")+"'"))
 [IO.File]::WriteAllText($runner,$code,(New-Object Text.UTF8Encoding($true)))
 $out=& {
  function Get-CimInstance { [pscustomobject]@{Product='Generic Fixture'} }
  function New-Item {throw 'Unexpected host write'}
  function New-ItemProperty {throw 'Unexpected registry write'}
  function Get-PnpDevice {throw 'Unexpected driver scan'}
  & $runner
 }
 Assert (@($out|Where-Object Status -eq 'Skipped').Count -eq 1) ('獨立入口安全略過且不寫主機：'+$relative)
}
# Build a source-only package with no driver payload; Autologon is only an existence fixture.
$genericPackage=Join-Path $fixture 'generic_package'
New-Item -ItemType Directory -Path $genericPackage|Out-Null
foreach($dir in @('core','modules')){
 foreach($file in @(Get-ChildItem -LiteralPath (Join-Path $packageRoot $dir) -Recurse -File|Where-Object {$_.FullName -notmatch '[\\/]Payload[\\/]|[\\/]Reports[\\/]' -and $_.Extension -notin @('.exe','.zip','.log')})){
  $relative=$file.FullName.Substring($packageRoot.Length).TrimStart('\')
  $destination=Join-Path $genericPackage $relative
  New-Item -ItemType Directory -Path (Split-Path $destination -Parent) -Force|Out-Null
  Copy-Item -LiteralPath $file.FullName -Destination $destination
 }
}
foreach($entry in @('Init.cmd','Windows.cmd','README.md')){Copy-Item -LiteralPath (Join-Path $packageRoot $entry) -Destination $genericPackage}
[IO.File]::WriteAllText((Join-Path $genericPackage 'modules\accounts\Autologon64.exe'),'existence fixture, never executed')
& (Join-Path $genericPackage 'core\Test-SetupPrerequisites.ps1') -PackageOnly -HardwareProfile Generic
$verificationHelper=Join-Path $genericPackage 'core\Verification.ps1'
Move-Item -LiteralPath $verificationHelper -Destination ($verificationHelper+'.fixture-backup')
$missingHelperRejected=$false
try{& (Join-Path $genericPackage 'core\Test-SetupPrerequisites.ps1') -PackageOnly -HardwareProfile Generic}catch{$missingHelperRejected=$_.Exception.Message -match 'Verification.ps1'}finally{Move-Item -LiteralPath ($verificationHelper+'.fixture-backup') -Destination $verificationHelper}
Assert $missingHelperRejected '缺少 Verification helper 的套件不得通過 PackageOnly'
Assert (-not(Test-Path (Join-Path $genericPackage 'modules\drivers\Payload'))) '通用 PackageOnly 完整檢查成功且未建立或要求 NUC payload'
$caught=$false;try{& (Join-Path $genericPackage 'core\Test-SetupPrerequisites.ps1') -PackageOnly -HardwareProfile NUC8 -DriverPackagePath (Join-Path $fixture 'missing')}catch{$caught=$true}
Assert $caught '相同無驅動包指定 NUC8 仍拒絕'
$selectionFile=Join-Path $fixture 'selection.json'
@{Computer='machine_a';UserSID='sid_a';HardwareProfile=@{DriverPackagePath='chosen'}}|ConvertTo-Json -Depth 4|Set-Content $selectionFile -Encoding UTF8
Assert ((Get-SetupSavedDriverSelection $selectionFile 'machine_a' 'sid_a') -eq 'chosen') '相同電腦與使用者續用明確選擇'
Assert ((Get-SetupSavedDriverSelection $selectionFile 'machine_b' 'sid_a') -eq '') '其他電腦不沿用驅動包'
Assert ((Get-SetupSavedDriverSelection $selectionFile 'machine_a' 'sid_b') -eq '') '其他帳號不沿用驅動包'
# Restore small fixture files, then export a standalone package and validate it from another directory.
[IO.File]::WriteAllText((Join-Path $payload 'driver1.zip'),'fixture')
$manifest|ConvertTo-Json|Set-Content (Join-Path $payload 'manifest.json') -Encoding UTF8
$exported=Join-Path $fixture '獨立 驅動包'
Push-Location $fixture
# GitHub runner TEMP may use RUNNER~1 while the provider resolves runneradmin.
# Derive the expected directory from the actual PowerShell location, not its 8.3 alias.
$expectedProviderOutput=Join-Path (Get-Location).ProviderPath '獨立 驅動包'
Assert ((Get-Location).ProviderPath -ine [Environment]::CurrentDirectory) '回歸測試確保 PowerShell 位置與 NET cwd 不同'
Write-Host ('Export diagnostic: ProviderLocation=['+(Get-Location).ProviderPath+']; NETcwd=['+[Environment]::CurrentDirectory+']; TEMP=['+$env:TEMP+']')
try{$exportResult=& (Join-Path $packageRoot 'script\package\Export-DriverPackage.ps1') -SourceDirectory $payload -OutputDirectory '.\獨立 驅動包'}finally{Pop-Location}
Write-Host ('Export diagnostic: Actual=['+$exportResult.OutputDirectory+']; ExpectedProvider=['+$expectedProviderOutput+']; FixtureAlias=['+$exported+']; ActualExists=['+(Test-Path -LiteralPath $exportResult.OutputDirectory)+']; ExpectedExists=['+(Test-Path -LiteralPath $exported)+']')
Assert ($exportResult.OutputDirectory -eq $expectedProviderOutput -and (Test-Path -LiteralPath $expectedProviderOutput -PathType Container) -and (Test-Path -LiteralPath $exported -PathType Container)) '獨立包相對輸出依 PowerShell 位置解析'
Assert ($exportResult.Count -eq 4 -and (Test-Path (Join-Path $exported 'Install.cmd'))) '導出獨立驅動包與可攜入口'
$standalone=& (Join-Path $exported 'modules\drivers\Install-Drivers.ps1') -DriverPackagePath $exported -PackageOnly
Assert ($standalone.Status -eq 'Passed') '獨立包只用自身 helper 完成唯讀驗證'
Assert (-not(Test-Path (Join-Path $exported 'script')) -and -not(Test-Path (Join-Path $exported 'test')) -and -not(Test-Path (Join-Path $exported '.github'))) '獨立包不攜帶維護工具且已獨立執行驗證'
@{SchemaVersion=1;HardwareProfile='Other';Architecture='x64';SupportedBoards=@('Other')}|ConvertTo-Json|Set-Content (Join-Path $exported 'package.json') -Encoding UTF8
$caught=$false;try{Test-SetupDriverPayload $hv $exported|Out-Null}catch{$caught=$true}
Assert $caught '其他型號的獨立包被拒絕'
Write-Host ('ALL PASS: '+$count+' hardware assertions; temporary fixtures only, no Windows settings changed.')