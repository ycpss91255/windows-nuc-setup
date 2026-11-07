#Requires -Version 5.1
[CmdletBinding()]
param(
 [Parameter(Mandatory=$true)][string]$Version,
 [Parameter(Mandatory=$true)][string]$OutputDirectory,
 [string]$PackageRoot=(Split-Path $PSScriptRoot -Parent),
 [ValidatePattern('^(HEAD|[a-fA-F0-9]{40})$')][string]$Revision='HEAD'
)
$ErrorActionPreference='Stop'
if($Version -cnotmatch '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'){throw '版本必須是 v主版.次版.修訂，例如 v1.0.0。'}
$PackageRoot=(Resolve-Path -LiteralPath $PackageRoot).Path
$commit=(& git -C $PackageRoot rev-parse --verify ($Revision+'^{commit}'))
if($LASTEXITCODE -ne 0 -or $commit -notmatch '^[a-fA-F0-9]{40}$'){throw '無法確認來源提交。'}
$files=@(& git -C $PackageRoot -c core.quotepath=false ls-tree -r --name-only $commit)
if($LASTEXITCODE -ne 0 -or -not $files.Count){throw '無法讀取提交中的來源檔案。'}
foreach($path in $files){
 $normalized=$path.Replace('\','/')
 if($normalized -match '(^|/)(Reports|TestResults|\.ssh|NUC-Init|Private|LocalConfig)(/|$)' -or
    $normalized -match '(?i)\.(exe|dll|zip|7z|rar|msi|msix|cab|iso|pfx|pem|key)$' -or
    $normalized -match '(?i)(^|/)(answer\.xml|unattend\.xml|autounattend\.xml|runtime\.json|owner\.json|state\.json|cleanup-result\.json|known_hosts.*|id_rsa.*|id_ed25519.*)$' -or
    $normalized -match '(?i)(^|/)[^/]*-(Result|Verification|Progress)\.json$'){
  throw ('拒絕將執行資料、秘密或安裝二進位放入來源版本包：'+$path)
 }
}
foreach($required in @('Init.cmd','Windows.cmd','README.md','Docs/GITHUB.md')){
 if($required -notin $files){throw ('來源提交缺少必要檔案：'+$required)}
}
$output=[IO.Path]::GetFullPath($OutputDirectory)
if(-not(Test-Path -LiteralPath $output)){New-Item -ItemType Directory -Path $output|Out-Null}
$stem='Windows-NUC-Setup-'+$Version+'-source'
$zip=Join-Path $output ($stem+'.zip')
$checksum=Join-Path $output ($stem+'.sha256')
$notes=Join-Path $output 'RELEASE-NOTES.md'
foreach($destination in @($zip,$checksum,$notes)){if(Test-Path -LiteralPath $destination){throw ('目的檔案已存在，未覆寫：'+$destination)}}
& git -C $PackageRoot archive --format=zip ('--prefix=Windows-NUC-Setup/') ('--output='+$zip) $commit
if($LASTEXITCODE -ne 0){throw '來源 ZIP 建立失敗。'}
$hash=(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
$utf8=New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText($checksum,($hash+'  '+[IO.Path]::GetFileName($zip)+"`n"),$utf8)
$body=@"
# Windows NUC 設定工具 $Version

發布流程會先執行 Windows CI 的語法、路徑與隔離測試；實際結果以對應 Actions 紀錄為準。本機單獨打包不代表已通過 CI。

- 來源提交：$commit
- 下載 source.zip 與對應 SHA256 清單後，先驗證檔案完整性。
- 這是程式來源包，不含裝置驅動與 Microsoft Autologon EXE；依 Docs/GITHUB.md 補齊必要二進位，再執行完整套件檢查。
- 不包含實機報告、續跑紀錄、密碼或私鑰。
- CI 不能代替 NUC 硬體、OOBE、驅動與重開機的實機驗證。

完整修改紀錄請查看 CHANGELOG.md。Release 下載檔長期保留；CI 測試報告僅短期保留 7 天。
"@
[IO.File]::WriteAllText($notes,$body,$utf8)
[pscustomobject]@{Version=$Version;Commit=$commit;FileCount=$files.Count;ZipPath=$zip;ChecksumPath=$checksum;NotesPath=$notes;SHA256=$hash}
