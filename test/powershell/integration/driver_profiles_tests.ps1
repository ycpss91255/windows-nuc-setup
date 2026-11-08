#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
. (Join-Path $root 'core/hardware.ps1')
function Assert([bool]$Value,[string]$Name){Write-Host ('@@ASSERT@@'+(@{Name=$Name;Passed=$Value}|ConvertTo-Json -Compress));if(-not $Value){throw $Name}}
function Reject([scriptblock]$Action,[string]$Name){$failed=$false;try{& $Action|Out-Null}catch{$failed=$true};Assert $failed $Name}
$temp=Join-Path ([IO.Path]::GetTempPath()) ('driver_profiles_'+[guid]::NewGuid().ToString('N'))
$registry=Join-Path $temp 'drivers';$dir=Join-Path $registry 'synthetic_board';[void][IO.Directory]::CreateDirectory($dir)
$profile=[ordered]@{SchemaVersion=1;ProfileId='synthetic_board';PackageDirectory='synthetic';Architecture='x64';SupportedBoards=@('SYNTHETIC-BOARD','SYNTHETIC-SECOND');Description='測試主機板'}
function SaveProfile {[IO.File]::WriteAllText((Join-Path $dir 'profile.json'),($profile|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))}
SaveProfile
$p=Get-SetupDriverProfile -BoardProduct SYNTHETIC-BOARD -ProfilesRoot $registry
Assert ($p.ProfileId -eq 'synthetic_board' -and $p.PackageDirectory -eq 'synthetic') '第二種暫存設定檔由共用registry精準選出'
Assert ($p.Description -ceq '測試主機板') 'Windows PowerShell 5.1正確讀取無BOM中文UTF8設定檔'
Assert ($null -eq (Get-SetupDriverProfile -BoardProduct 'SYNTHETIC-BOARD-extra' -ProfilesRoot $registry)) '板號不得部分命中'
$h=Get-SetupHardwareProfile -BoardProduct SYNTHETIC-BOARD -ProfilesRoot $registry -DriverPackagePath $temp
Assert ($h.DriverProfileId -eq 'synthetic_board' -and -not $h.IsNuc8) '通用profile與NUC專屬判斷分開'
Assert ((Get-SetupModuleDecision install_drivers.ps1 $h).Applicable) '其他已登錄板可執行共用驅動模組'
Assert (-not (Get-SetupModuleDecision apply_amd_privacy_settings.ps1 $h).Applicable) '其他板不套用NUC AMD隱私'
$duplicate=Join-Path $registry 'duplicate';[void][IO.Directory]::CreateDirectory($duplicate)
$profile.ProfileId='duplicate';$profile|ConvertTo-Json|Set-Content (Join-Path $duplicate 'profile.json') -Encoding UTF8
Reject {Get-SetupDriverProfile -BoardProduct SYNTHETIC-BOARD -ProfilesRoot $registry} '重複板號設定檔拒絕自動選型'
Remove-Item -LiteralPath $duplicate -Recurse;$profile.ProfileId='synthetic_board'
$profile.PackageDirectory='../escape';SaveProfile
Reject {Get-SetupDriverProfile -BoardProduct SYNTHETIC-BOARD -ProfilesRoot $registry} 'package目錄不允許跳脫'
$profile.PackageDirectory='synthetic';SaveProfile
$package=Join-Path $temp 'payload';[void][IO.Directory]::CreateDirectory($package)
[IO.File]::WriteAllText((Join-Path $package 'fixture.zip'),'inert fixture')
$entry=@{Id='example';File='fixture.zip';SHA256=(Get-FileHash (Join-Path $package 'fixture.zip')).Hash;SourceUrl='https://www.intel.com/driver';PackageVersion='1.0';Drivers=@(@{Id='device';InfPath='device.inf';HardwareIds=@('PCI\VEN_1234&DEV_5678');Provider='Example';DriverVersion='1.0.0.0';Architecture='amd64';MinimumBuild=22000})}
@{SchemaVersion=2;Packages=@($entry)}|ConvertTo-Json -Depth 12|Set-Content (Join-Path $package 'manifest.json') -Encoding UTF8
$export=Join-Path $temp 'export'
$result=& (Join-Path $root 'script/package/export_driver_package.ps1') -SourceDirectory $package -OutputDirectory $export -ProfileId synthetic_board -ProfilesRoot $registry
Assert ($result.Status -eq 'Passed') '共用export可輸出第二種profile'
Assert (Test-Path (Join-Path $export 'drivers/synthetic_board/profile.json')) '輸出包含自足registry'
$identity=Get-Content (Join-Path $export 'package.json') -Raw|ConvertFrom-Json
Assert ($identity.SchemaVersion -eq 2 -and $identity.ProfileId -eq 'synthetic_board') '版本2包身分綁定profile'
Assert ($identity.ProfileSHA256 -eq (Get-FileHash (Join-Path $dir 'profile.json')).Hash) '身分記錄profile原始位元組hash'
Assert ((Test-SetupDriverPayload $h $export).Status -eq 'Passed') '已選型第二種板可驗證輸出包'
$entryPath=Join-Path $export 'modules/drivers/install_drivers.ps1'
$command="& '"+$entryPath.Replace("'","''")+"' -PackageOnly -DriverPackagePath '"+$export.Replace("'","''")+"' | ConvertTo-Json -Compress"
$encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
$cli=@(& powershell.exe -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded 2>&1)
Assert ($LASTEXITCODE -eq 0 -and ($cli -join '') -match '"Status":"Passed"' -and ($cli -join '') -match '"Count":1') '真交付CLI離線驗包支援第二個機型，不固定NUC板號'
$offlineResult=@(. $entryPath -PackageOnly -DriverPackagePath $export)
Assert ($offlineResult.Count -eq 1 -and $offlineResult[0].Status -eq 'Passed') '同程序正式入口同樣離線驗證第二機型，保留來源量測'
. (Join-Path $root 'core/hardware.ps1')
$wrong=Get-SetupHardwareProfile -BoardProduct NUC8i7HVB
Reject {Test-SetupDriverPayload $wrong $export} '其他合法profile的包不能跨板安裝'
$identity.SupportedBoards=@('NUC8i7HVB');$identity|ConvertTo-Json|Set-Content (Join-Path $export 'package.json') -Encoding UTF8
Reject {Test-SetupDriverPayload $wrong $export} '只竄改包自宣板號不能放行'
$identity.SupportedBoards=@('SYNTHETIC-BOARD','SYNTHETIC-BOARD');$identity|ConvertTo-Json|Set-Content (Join-Path $export 'package.json') -Encoding UTF8
Reject {Test-SetupDriverPayload $h $export} '自宣板號重複不能冒充完整白名單'
$identity.SupportedBoards=@('SYNTHETIC-BOARD','SYNTHETIC-SECOND');$identity|ConvertTo-Json|Set-Content (Join-Path $export 'package.json') -Encoding UTF8
Add-Content (Join-Path $export 'drivers/synthetic_board/profile.json') ' '
Reject {Test-SetupDriverPayload $h $export} '包內profile原始bytes改動拒絕'
Write-Host 'ALL PASS: profile registry identity and export; TEMP only.'
