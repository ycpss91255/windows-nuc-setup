#Requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$SourceDirectory,[Parameter(Mandatory=$true)][string]$OutputDirectory)
$ErrorActionPreference='Stop'
$packageRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $packageRoot 'core/hardware.ps1')
$source=(Resolve-Path -LiteralPath $SourceDirectory).Path
$output=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
if(Test-Path -LiteralPath $output){throw '輸出目錄已存在，未覆寫；請選擇新目錄。'}
$null=Test-SetupDriverPayload -Hardware (Get-SetupHardwareProfile -BoardProduct 'NUC8i7HVB') -DriverPackagePath $source -AllowLegacyManifest
$manifest=Get-Content -LiteralPath (Join-Path $source 'manifest.json') -Raw|ConvertFrom-Json
New-Item -ItemType Directory -Path (Join-Path $output 'core'),(Join-Path $output 'modules\drivers') -Force|Out-Null
foreach($entry in $manifest){Copy-Item -LiteralPath (Join-Path $source $entry.File) -Destination $output}
Copy-Item -LiteralPath (Join-Path $source 'manifest.json') -Destination $output
@{SchemaVersion=1;HardwareProfile='NUC8';Architecture='x64';SupportedBoards=@('NUC8i7HVB','NUC8i7HNB')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $output 'package.json') -Encoding UTF8
Copy-Item -LiteralPath (Join-Path $packageRoot 'core/hardware.ps1') -Destination (Join-Path $output 'core')
Copy-Item -LiteralPath (Join-Path $packageRoot 'modules\drivers\install_drivers.ps1') -Destination (Join-Path $output 'modules\drivers')
$cmd='@echo off'+"`r`n"+'powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0modules\drivers\install_drivers.ps1" -DriverPackagePath "%~dp0." %*'+"`r`n"
[IO.File]::WriteAllText((Join-Path $output 'install.cmd'),$cmd,[Text.Encoding]::ASCII)
$readme=@"
# NUC8 獨立驅動包

完整複製此資料夾到目標電腦，雙擊 install.cmd。管理員權限由安裝器提示；錯誤機型安全略過。

| 整機／套件型號 | 接受的主機板 Product |
| --- | --- |
| NUC8i7HVK；同板 NUC8i7HVKVA／NUC8i7HVKVAW | NUC8i7HVB |
| NUC8i7HNK；同板 NUC8i7HNKQC | NUC8i7HNB |

依 [ASUS 官方 NUC 規格索引](https://zentalk.asus.com/t5/faq/nuc-technical-product-specifications-for-nuc-products/ta-p/451363) 的 BIOS 識別對照。腳本實際讀取 Win32_BaseBoard.Product，去除首尾空白後精確比對白名單，不依外殼型號猜測；不是所有 NUC8 都可使用。OEM 若回報其他值會略過。

這是型號對照與安裝條件，不代表每個整機變體已實測。四個封存檔不是完整的所有裝置驅動集；仍須依裝置管理員與 Windows Update 檢查其他驅動。AMD 封存檔 GFX-Radeon-Win10-23.10.01.46.zip 在官方列為 Windows 10 64-bit，不能宣稱 Windows 11 官方認證；本工具在 Windows 11 的結果須逐機驗證。

只檢查包完整性（不安裝、不檢查目前電腦是否相容）：install.cmd -PackageOnly。此結果不能當成目前主機可安裝的證明。

可由 Windows 設定工具的 DriverPackagePath 選擇本目錄；此包不需要原主包路徑。安裝日誌位於 modules/drivers/driver_logs；既有 ProgramData NUC8-Setup 快取識別保留。獨立包不依賴 script/test/.github。完整性檢查會核對 package.json 的型號／架構與 manifest.json 的四個封存檔雜湊。
"@
[IO.File]::WriteAllText((Join-Path $output 'readme.md'),$readme,(New-Object Text.UTF8Encoding($true)))
$null=Test-SetupDriverPayload -Hardware (Get-SetupHardwareProfile -BoardProduct 'NUC8i7HVB') -DriverPackagePath $output
[pscustomobject]@{OutputDirectory=$output;Count=$manifest.Count;Status='Passed'}