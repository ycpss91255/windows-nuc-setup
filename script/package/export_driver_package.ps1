#Requires -Version 5.1
param([Parameter(Mandatory=$true)][string]$SourceDirectory,[Parameter(Mandatory=$true)][string]$OutputDirectory,[string]$ProfileId='nuc8i7hvk_hnk',[string]$ProfilesRoot='')
$ErrorActionPreference='Stop'
$packageRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $packageRoot 'core/hardware.ps1')
$source=(Resolve-Path -LiteralPath $SourceDirectory).Path
$output=$ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
if(Test-Path -LiteralPath $output){throw '輸出目錄已存在，未覆寫；請選擇新目錄。'}
$profile=Get-SetupDriverProfile -ProfileId $ProfileId -ProfilesRoot $ProfilesRoot
if(-not $profile){throw '找不到指定的驅動設定檔。'}
$hardware=Get-SetupHardwareProfile -BoardProduct $profile.SupportedBoards[0] -ProfilesRoot $ProfilesRoot
$null=Test-SetupDriverPayload -Hardware $hardware -DriverPackagePath $source -AllowLegacyManifest
$sourceManifest=Get-Content -LiteralPath (Join-Path $source 'manifest.json') -Raw|ConvertFrom-Json
$manifest=@(Get-SetupDriverManifestEntries -Manifest (Get-Content -LiteralPath (Join-Path $source 'manifest.json') -Raw|ConvertFrom-Json))
New-Item -ItemType Directory -Path (Join-Path $output 'core'),(Join-Path $output 'modules\drivers') -Force|Out-Null
foreach($entry in $manifest){Copy-Item -LiteralPath (Join-Path $source $entry.File) -Destination $output}
Copy-Item -LiteralPath (Join-Path $source 'manifest.json') -Destination $output
$profileDirectory=Join-Path $output ('drivers/'+$profile.ProfileId)
[void][IO.Directory]::CreateDirectory($profileDirectory)
Copy-Item -LiteralPath $profile.ProfilePath -Destination (Join-Path $profileDirectory 'profile.json')
if($sourceManifest.SchemaVersion -eq 2){
 @{SchemaVersion=2;ProfileId=$profile.ProfileId;ProfileSHA256=$profile.ProfileSHA256;Architecture=$profile.Architecture;SupportedBoards=@($profile.SupportedBoards)}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $output 'package.json') -Encoding UTF8
}else{
 if($profile.ProfileId -cne 'nuc8i7hvk_hnk'){throw '舊四檔格式僅適用原 NUC 設定檔。'}
 @{SchemaVersion=1;HardwareProfile='NUC8';Architecture='x64';SupportedBoards=@('NUC8i7HVB','NUC8i7HNB')}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $output 'package.json') -Encoding UTF8
}
Copy-Item -LiteralPath (Join-Path $packageRoot 'core/hardware.ps1') -Destination (Join-Path $output 'core')
Copy-Item -LiteralPath (Join-Path $packageRoot 'modules\drivers\install_drivers.ps1') -Destination (Join-Path $output 'modules\drivers')
foreach($helper in @('driver_archive_library.ps1','driver_plan_library.ps1','driver_installation_library.ps1')){Copy-Item -LiteralPath (Join-Path $packageRoot ('modules/drivers/'+$helper)) -Destination (Join-Path $output 'modules/drivers')}
[void][IO.Directory]::CreateDirectory((Join-Path $output 'modules/updates'))
Copy-Item -LiteralPath (Join-Path $packageRoot 'modules/updates/update_stage_library.ps1') -Destination (Join-Path $output 'modules/updates')
$cmd='@echo off'+"`r`n"+'powershell.exe -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0modules\drivers\install_drivers.ps1" -DriverPackagePath "%~dp0." %*'+"`r`n"
[IO.File]::WriteAllText((Join-Path $output 'install.cmd'),$cmd,[Text.Encoding]::ASCII)
$readme=@"
# 獨立驅動包：$($profile.ProfileId)

完整複製此資料夾到目標電腦，執行 install.cmd；管理員權限由安裝器提示。依 Win32_BaseBoard.Product 精準比對下列板號，不依使用者名稱、磁碟代號或原 repo 路徑。

架構：$($profile.Architecture)；接受板號：$($profile.SupportedBoards -join '、')。

未符合設定檔或未選擇包時略過。逐裝置比對硬體 ID、provider、INF 版本及 OS 範圍；保留較新驅動，不以套件版號代替所有 INF 版本。必要 SWC 先加入後安裝父裝置並重新枚舉讀回；Extension 需確認 active 裝置關聯。

唯讀檢查包完整性：install.cmd -PackageOnly。此結果不能當成目前主機可安裝的證明。版本 2 package.json 以原始 SHA256 綁定 drivers/$($profile.ProfileId)/profile.json；manifest.json 記錄全部來源、封存檔及 payload 雜湊。完整性驗證不等於目前每個裝置皆已安裝。

日誌位於 modules/drivers/driver_logs。可從主 Windows 工具的 DriverPackagePath 選擇本目錄，或獨立使用；不依賴 script、test 或 .github。不執行來源安裝 EXE 或韌體工具。詳細官方來源及每個 INF 版本見 manifest.json。
"@
if(Test-Path -LiteralPath (Join-Path (Split-Path $profile.ProfilePath -Parent) 'readme.md')){
 Copy-Item -LiteralPath (Join-Path (Split-Path $profile.ProfilePath -Parent) 'readme.md') -Destination (Join-Path $profileDirectory 'readme.md')
}
[IO.File]::WriteAllText((Join-Path $output 'readme.md'),$readme,(New-Object Text.UTF8Encoding($true)))
$null=Test-SetupDriverPayload -Hardware $hardware -DriverPackagePath $output
[pscustomobject]@{OutputDirectory=$output;Count=$manifest.Count;Status='Passed'}
